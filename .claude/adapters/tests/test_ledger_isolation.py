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
        # Readers run the same resolver (rollup default; cost-report.sh is
        # pinned by tests/unit/cheval-cost-rollup.bats).
        assert default_ledger_path() == _real(env_path)

    def test_reader_default_fails_closed_like_the_writer(self, monkeypatch, tmp_path):
        """round-2 dissent DISS-001: a path the resolver refuses must not make
        the reader silently open .run/cost-ledger.jsonl instead."""
        real = tmp_path / "real.jsonl"
        real.write_text("")
        link = tmp_path / "link.jsonl"
        link.symlink_to(real)
        monkeypatch.setenv(COST_LEDGER_ENV, str(link))
        with pytest.raises(ConfigError):
            default_ledger_path()
        from loa_cheval.metering.rollup import main as rollup_main
        assert rollup_main(["--by", "agent", "--json"]) == 2
        # An explicit --ledger never consults the resolver.
        (tmp_path / "ok.jsonl").write_text("")
        assert rollup_main(["--ledger", str(tmp_path / "ok.jsonl"), "--json"]) == 0

    def test_falls_back_to_config_when_env_unset(self, monkeypatch, tmp_path):
        monkeypatch.delenv(COST_LEDGER_ENV, raising=False)
        cfg_path = tmp_path / "cfg-ledger.jsonl"
        assert resolve_cost_ledger_path({"ledger_path": str(cfg_path)}) == _real(cfg_path)
        # Empty config value is "unset", not "the empty path".
        monkeypatch.chdir(tmp_path)
        assert resolve_cost_ledger_path({"ledger_path": ""}) == _real(PROJECT_ROOT / DEFAULT_COST_LEDGER_PATH)

    def test_relative_config_path_is_anchored_at_the_project_root(self, monkeypatch, tmp_path):
        """review round-1 high #5: the merged config says `.run/cost-ledger.jsonl`;
        cheval invoked from a subdirectory must not fork the ledger (the MODELINV
        twin already anchors to the repo root)."""
        monkeypatch.delenv(COST_LEDGER_ENV, raising=False)
        monkeypatch.chdir(tmp_path)
        assert resolve_cost_ledger_path({"ledger_path": ".run/cost-ledger.jsonl"}) == _real(
            PROJECT_ROOT / ".run" / "cost-ledger.jsonl"
        )
        # An env path stays CWD-relative (test / operator redirect, documented).
        (tmp_path / "here").mkdir()
        monkeypatch.setenv(COST_LEDGER_ENV, "here/ledger.jsonl")
        assert resolve_cost_ledger_path({"ledger_path": ".run/cost-ledger.jsonl"}) == _real(
            tmp_path / "here" / "ledger.jsonl"
        )

    def test_default_when_neither(self, monkeypatch, tmp_path):
        monkeypatch.delenv(COST_LEDGER_ENV, raising=False)
        monkeypatch.chdir(tmp_path)
        expected = _real(PROJECT_ROOT / ".run" / "cost-ledger.jsonl")
        assert DEFAULT_COST_LEDGER_PATH == ".run/cost-ledger.jsonl"
        assert resolve_cost_ledger_path({}) == expected
        assert resolve_cost_ledger_path(None) == expected
        # The default never depends on the CWD: nothing is created here.
        assert not (tmp_path / ".run").exists()

    def test_default_resolves_under_the_project_root_from_any_cwd(self, tmp_path):
        """Subprocess twin of the above: a fresh interpreter, no env override, a
        foreign CWD — the resolver still names <repo>/.run/cost-ledger.jsonl."""
        env = {k: v for k, v in os.environ.items() if k != COST_LEDGER_ENV}
        code = (
            f"import sys; sys.path.insert(0, {str(PROJECT_ROOT / '.claude' / 'adapters')!r}); "
            "from loa_cheval.metering.ledger import resolve_cost_ledger_path; "
            "print(resolve_cost_ledger_path({}))"
        )
        proc = subprocess.run([sys.executable, "-c", code], cwd=str(tmp_path), env=env,
                              capture_output=True, text=True, timeout=60)
        assert proc.returncode == 0, proc.stderr
        assert proc.stdout.strip() == _real(PROJECT_ROOT / ".run" / "cost-ledger.jsonl")


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

    @pytest.mark.parametrize("target_kind", ["directory", "devnull"])
    def test_existing_non_regular_target_rejected(self, monkeypatch, tmp_path, target_kind):
        """review round-1 high #5: a directory or /dev/null passed the old checks
        and failed inside BudgetEnforcer.post_call — after the billed call and
        inside the retry loop. It is INVALID_CONFIG at resolve time now."""
        if target_kind == "directory":
            target = tmp_path / "ledger-dir"
            target.mkdir()
        else:
            target = Path("/dev/null")
            if not target.exists():
                pytest.skip("/dev/null absent")
        monkeypatch.setenv(COST_LEDGER_ENV, str(target))
        with pytest.raises(ConfigError) as excinfo:
            resolve_cost_ledger_path({})
        assert excinfo.value.code == "INVALID_CONFIG"
        assert "not a regular file" in str(excinfo.value)
        monkeypatch.delenv(COST_LEDGER_ENV)
        with pytest.raises(ConfigError):
            resolve_cost_ledger_path({"ledger_path": str(target)})

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
        """The invariant, not the mechanism (review round-1 medium 3): both
        ledger paths are set and NEITHER resolves under the repo's .run/ —
        an operator-level export elsewhere (the FR-6 runbook's recommendation)
        satisfies it just as the conftest's tmp_path redirect does."""
        repo_run = _real(PROJECT_ROOT / ".run") + os.sep
        for var in (COST_LEDGER_ENV, MODELINV_ENV):
            value = os.environ.get(var)
            assert value, f"{var} must be set (tests/conftest.py sets it when unset)"
            assert not _real(Path(value)).startswith(repo_run), (
                f"{var}={value!r} points into the repo's .run/ — the adapter suite "
                "would append test rows to a production ledger"
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
