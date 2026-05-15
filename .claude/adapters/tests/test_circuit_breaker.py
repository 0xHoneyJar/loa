"""Tests for the (provider, auth_type)-keyed circuit breaker (cycle-110 FR-0)."""

import json
import os
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.circuit_breaker import (  # noqa: E402
    AUTH_TYPE_AWS_IAM,
    AUTH_TYPE_HEADLESS,
    AUTH_TYPE_HTTP_API,
    CLOSED,
    HALF_OPEN,
    OPEN,
    CircuitBreakerMigrationTimeout,
    _migrate_legacy_state_if_present,
    _state_file_path,
    check_state,
    cleanup_stale_files,
    cleanup_stale_tempfiles,
    increment_probe,
    list_buckets,
    record_failure,
    record_success,
)


# Default config for tests
CB_CONFIG = {
    "routing": {
        "circuit_breaker": {
            "failure_threshold": 3,
            "reset_timeout_seconds": 5,
            "half_open_max_probes": 1,
            "count_window_seconds": 60,
        }
    }
}


# ---------------------------------------------------------------------------
# Auth-type validation
# ---------------------------------------------------------------------------


class TestAuthTypeValidation:
    """Closed-enum validation ([PRD:FR-2.2])."""

    def test_state_file_path_rejects_invalid_auth_type(self, tmp_path):
        with pytest.raises(ValueError, match="auth_type"):
            _state_file_path("openai", "bogus", str(tmp_path))

    def test_check_state_rejects_invalid_auth_type(self, tmp_path):
        with pytest.raises(ValueError):
            check_state("openai", "bogus", CB_CONFIG, str(tmp_path))

    def test_path_includes_auth_type(self, tmp_path):
        p = _state_file_path("openai", AUTH_TYPE_HEADLESS, str(tmp_path))
        assert p.endswith("circuit-breaker-openai-headless.json")


# ---------------------------------------------------------------------------
# check_state / record_failure / record_success per bucket
# ---------------------------------------------------------------------------


class TestCheckState:
    """Per-bucket state machine."""

    def test_default_closed(self, tmp_path):
        state = check_state("openai", AUTH_TYPE_HTTP_API, CB_CONFIG, str(tmp_path))
        assert state == CLOSED

    def test_reads_existing_state(self, tmp_path):
        path = tmp_path / "circuit-breaker-openai-headless.json"
        path.write_text(json.dumps({
            "provider": "openai",
            "auth_type": AUTH_TYPE_HEADLESS,
            "state": OPEN,
            "failure_count": 5,
            "opened_at": time.time() + 100,
        }))
        state = check_state("openai", AUTH_TYPE_HEADLESS, CB_CONFIG, str(tmp_path))
        assert state == OPEN

    def test_open_transitions_to_half_open(self, tmp_path):
        path = tmp_path / "circuit-breaker-openai-http_api.json"
        path.write_text(json.dumps({
            "provider": "openai",
            "auth_type": AUTH_TYPE_HTTP_API,
            "state": OPEN,
            "failure_count": 5,
            "opened_at": time.time() - 10,
        }))
        state = check_state("openai", AUTH_TYPE_HTTP_API, CB_CONFIG, str(tmp_path))
        assert state == HALF_OPEN

    def test_corrupted_file_returns_closed(self, tmp_path):
        path = tmp_path / "circuit-breaker-openai-headless.json"
        path.write_text("not json")
        state = check_state("openai", AUTH_TYPE_HEADLESS, CB_CONFIG, str(tmp_path))
        assert state == CLOSED


class TestRecordFailure:
    def test_accumulates_failures(self, tmp_path):
        run_dir = str(tmp_path)
        record_failure("openai", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir)
        record_failure("openai", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir)
        assert check_state("openai", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir) == CLOSED

    def test_trips_at_threshold(self, tmp_path):
        run_dir = str(tmp_path)
        for _ in range(3):
            record_failure("openai", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir)
        assert check_state("openai", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir) == OPEN

    def test_half_open_failure_reopens(self, tmp_path):
        run_dir = str(tmp_path)
        path = tmp_path / "circuit-breaker-openai-http_api.json"
        path.write_text(json.dumps({
            "provider": "openai",
            "auth_type": AUTH_TYPE_HTTP_API,
            "state": HALF_OPEN,
            "failure_count": 3,
            "opened_at": time.time() - 10,
            "half_open_probes": 0,
        }))
        assert record_failure(
            "openai", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir
        ) == OPEN

    def test_count_window_resets(self, tmp_path):
        run_dir = str(tmp_path)
        config = {
            "routing": {
                "circuit_breaker": {
                    "failure_threshold": 3,
                    "reset_timeout_seconds": 5,
                    "count_window_seconds": 1,
                }
            }
        }
        record_failure("openai", AUTH_TYPE_HTTP_API, config, run_dir)
        record_failure("openai", AUTH_TYPE_HTTP_API, config, run_dir)
        path = tmp_path / "circuit-breaker-openai-http_api.json"
        data = json.loads(path.read_text())
        data["last_failure_ts"] = time.time() - 5
        path.write_text(json.dumps(data))
        assert record_failure(
            "openai", AUTH_TYPE_HTTP_API, config, run_dir
        ) == CLOSED


class TestRecordSuccess:
    def test_half_open_success_closes(self, tmp_path):
        run_dir = str(tmp_path)
        path = tmp_path / "circuit-breaker-openai-headless.json"
        path.write_text(json.dumps({
            "provider": "openai",
            "auth_type": AUTH_TYPE_HEADLESS,
            "state": HALF_OPEN,
            "failure_count": 3,
            "opened_at": time.time() - 10,
            "half_open_probes": 1,
        }))
        assert record_success(
            "openai", AUTH_TYPE_HEADLESS, CB_CONFIG, run_dir
        ) == CLOSED

    def test_closed_success_resets_count(self, tmp_path):
        run_dir = str(tmp_path)
        path = tmp_path / "circuit-breaker-openai-http_api.json"
        path.write_text(json.dumps({
            "provider": "openai",
            "auth_type": AUTH_TYPE_HTTP_API,
            "state": CLOSED,
            "failure_count": 2,
            "last_failure_ts": time.time(),
        }))
        record_success("openai", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir)
        data = json.loads(path.read_text())
        assert data["failure_count"] == 0


class TestBucketIsolation:
    """FR-0.4 anti-masking — buckets do NOT share state across auth_types."""

    def test_headless_trip_does_not_open_http_api(self, tmp_path):
        run_dir = str(tmp_path)
        for _ in range(3):
            record_failure("google", AUTH_TYPE_HEADLESS, CB_CONFIG, run_dir)
        # headless OPEN; http_api still CLOSED
        assert check_state("google", AUTH_TYPE_HEADLESS, CB_CONFIG, run_dir) == OPEN
        assert check_state("google", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir) == CLOSED

    def test_http_api_trip_does_not_open_headless(self, tmp_path):
        run_dir = str(tmp_path)
        for _ in range(3):
            record_failure("google", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir)
        assert check_state("google", AUTH_TYPE_HTTP_API, CB_CONFIG, run_dir) == OPEN
        assert check_state("google", AUTH_TYPE_HEADLESS, CB_CONFIG, run_dir) == CLOSED


class TestFullLifecycle:
    def test_closed_open_halfopen_closed(self, tmp_path):
        run_dir = str(tmp_path)
        config = {
            "routing": {
                "circuit_breaker": {
                    "failure_threshold": 2,
                    "reset_timeout_seconds": 1,
                    "half_open_max_probes": 1,
                    "count_window_seconds": 60,
                }
            }
        }
        assert check_state("openai", AUTH_TYPE_HTTP_API, config, run_dir) == CLOSED
        record_failure("openai", AUTH_TYPE_HTTP_API, config, run_dir)
        assert record_failure(
            "openai", AUTH_TYPE_HTTP_API, config, run_dir
        ) == OPEN

        path = tmp_path / "circuit-breaker-openai-http_api.json"
        data = json.loads(path.read_text())
        data["opened_at"] = time.time() - 5
        path.write_text(json.dumps(data))

        assert check_state("openai", AUTH_TYPE_HTTP_API, config, run_dir) == HALF_OPEN
        record_success("openai", AUTH_TYPE_HTTP_API, config, run_dir)
        assert check_state("openai", AUTH_TYPE_HTTP_API, config, run_dir) == CLOSED


# ---------------------------------------------------------------------------
# Legacy migration (T1.2 + T1.4) — AC1.6
# ---------------------------------------------------------------------------


class TestLegacyMigration:
    """AC1.6 — legacy state preserved into http_api bucket; symlink created."""

    def _write_legacy(self, tmp_path, **state):
        legacy = tmp_path / "circuit-breaker-openai.json"
        payload = {
            "provider": "openai",
            "state": OPEN,
            "failure_count": 7,
            "last_failure_ts": 1715000000.0,
            "opened_at": 1715000000.0,
            "half_open_probes": 0,
        }
        payload.update(state)
        legacy.write_text(json.dumps(payload))
        return legacy

    def test_legacy_state_preserved_into_http_api(self, tmp_path):
        legacy = self._write_legacy(tmp_path)
        _migrate_legacy_state_if_present("openai", str(tmp_path))

        http_api_path = tmp_path / "circuit-breaker-openai-http_api.json"
        assert http_api_path.is_file()
        assert not http_api_path.is_symlink()
        data = json.loads(http_api_path.read_text())
        assert data["state"] == OPEN
        assert data["failure_count"] == 7
        assert data["auth_type"] == AUTH_TYPE_HTTP_API

        # Headless and aws_iam buckets seeded CLOSED.
        head = tmp_path / "circuit-breaker-openai-headless.json"
        assert head.is_file()
        head_data = json.loads(head.read_text())
        assert head_data["state"] == CLOSED
        assert head_data["auth_type"] == AUTH_TYPE_HEADLESS

        # Transitional symlink created at legacy path.
        assert legacy.is_symlink()
        assert os.readlink(str(legacy)) == "circuit-breaker-openai-http_api.json"

    def test_check_state_auto_migrates_on_first_read(self, tmp_path):
        """Calling check_state for any auth_type triggers migration."""
        self._write_legacy(tmp_path, state=OPEN)
        # First read uses the headless bucket; legacy migration still runs.
        state = check_state(
            "openai", AUTH_TYPE_HEADLESS, CB_CONFIG, str(tmp_path)
        )
        # Headless gets CLOSED-default; http_api inherits legacy state.
        assert state == CLOSED
        http_api_data = json.loads(
            (tmp_path / "circuit-breaker-openai-http_api.json").read_text()
        )
        # opened_at far in the past → check_state on http_api would transition.
        # We just verify the state was preserved on disk.
        assert http_api_data["failure_count"] == 7

    def test_idempotent_on_repeat(self, tmp_path):
        self._write_legacy(tmp_path)
        _migrate_legacy_state_if_present("openai", str(tmp_path))
        # First migration removed legacy and created symlink.
        first_state = json.loads(
            (tmp_path / "circuit-breaker-openai-http_api.json").read_text()
        )
        # Second call must be a no-op.
        _migrate_legacy_state_if_present("openai", str(tmp_path))
        second_state = json.loads(
            (tmp_path / "circuit-breaker-openai-http_api.json").read_text()
        )
        assert first_state == second_state

    def test_symlink_is_not_migrated(self, tmp_path):
        """C13 closure: existing transitional symlink is NOT re-migrated."""
        # Simulate post-migration state: symlink + http_api bucket.
        legacy = tmp_path / "circuit-breaker-openai.json"
        target = tmp_path / "circuit-breaker-openai-http_api.json"
        target.write_text(json.dumps({
            "provider": "openai",
            "auth_type": AUTH_TYPE_HTTP_API,
            "state": OPEN,
            "failure_count": 3,
            "last_failure_ts": None,
            "opened_at": time.time(),
            "half_open_probes": 0,
        }))
        os.symlink("circuit-breaker-openai-http_api.json", str(legacy))

        _migrate_legacy_state_if_present("openai", str(tmp_path))

        # Symlink still exists with same target.
        assert legacy.is_symlink()
        assert os.readlink(str(legacy)) == "circuit-breaker-openai-http_api.json"
        # http_api state unchanged.
        data = json.loads(target.read_text())
        assert data["failure_count"] == 3

    def test_corrupted_legacy_fails_open(self, tmp_path):
        """T1.7: corrupted legacy → CLOSED bucket + [L4-MIGRATION-CORRUPT] marker."""
        legacy = tmp_path / "circuit-breaker-openai.json"
        legacy.write_text("not-json{{")

        _migrate_legacy_state_if_present("openai", str(tmp_path))

        http_api_path = tmp_path / "circuit-breaker-openai-http_api.json"
        assert http_api_path.is_file()
        data = json.loads(http_api_path.read_text())
        assert data["state"] == CLOSED
        assert data["failure_count"] == 0

        # Journal marker emitted.
        journal = tmp_path / "substrate-health-journal.jsonl"
        assert journal.is_file()
        entry = json.loads(journal.read_text().splitlines()[0])
        assert entry["marker"] == "L4-MIGRATION-CORRUPT"
        assert entry["provider"] == "openai"
        assert entry["action"] == "cold-start-fail-open"

    def test_overwrite_check_drops_legacy_when_http_api_has_state(self, tmp_path):
        """C3 closure: existing (provider, http_api) bucket with state wins."""
        # http_api bucket already exists with state.
        http_api = tmp_path / "circuit-breaker-openai-http_api.json"
        newer_state = {
            "provider": "openai",
            "auth_type": AUTH_TYPE_HTTP_API,
            "state": OPEN,
            "failure_count": 99,
            "last_failure_ts": time.time(),
            "opened_at": time.time(),
            "half_open_probes": 0,
        }
        http_api.write_text(json.dumps(newer_state))

        # Legacy file with different (older) state.
        self._write_legacy(tmp_path, state=CLOSED, failure_count=1)

        _migrate_legacy_state_if_present("openai", str(tmp_path))

        # Existing http_api state wins; legacy was dropped.
        data = json.loads(http_api.read_text())
        assert data["failure_count"] == 99
        assert data["state"] == OPEN

        # Legacy file unlinked; symlink created.
        legacy = tmp_path / "circuit-breaker-openai.json"
        assert legacy.is_symlink()

    def test_no_legacy_is_noop(self, tmp_path):
        """Fast-path: missing legacy file → no-op (no side effects)."""
        _migrate_legacy_state_if_present("openai", str(tmp_path))
        assert list(tmp_path.iterdir()) == []


# ---------------------------------------------------------------------------
# Migration lock timeout (FR-0.5 + SDD §5.3)
# ---------------------------------------------------------------------------


class TestMigrationLockTimeout:
    def test_timeout_raises_typed_exception(self, tmp_path, monkeypatch):
        """Lock contention beyond timeout raises CircuitBreakerMigrationTimeout."""
        # Drop the timeout to a tiny value so the test runs fast.
        from loa_cheval.routing import circuit_breaker as cb_mod

        monkeypatch.setattr(cb_mod, "MIGRATION_LOCK_TIMEOUT_SECONDS", 0.2)

        # Pre-acquire the lock in this process.
        lock_path = cb_mod._migration_lock_path(str(tmp_path))
        held_fd = cb_mod._acquire_migration_lock(lock_path)
        try:
            # Now another caller in the same process can't get LOCK_EX_NB.
            # We simulate by calling _acquire_migration_lock again.
            with pytest.raises(CircuitBreakerMigrationTimeout) as exc:
                cb_mod._acquire_migration_lock(lock_path, timeout_seconds=0.1)
            assert exc.value.timeout_seconds == 0.1
        finally:
            cb_mod._release_migration_lock(held_fd)


# ---------------------------------------------------------------------------
# list_buckets / substrate-health surfacing
# ---------------------------------------------------------------------------


class TestListBuckets:
    def test_enumerates_all_buckets(self, tmp_path):
        # Pre-seed two providers / mixed auth_types.
        for fname, payload in [
            ("circuit-breaker-google-http_api.json", {"provider": "google", "auth_type": "http_api", "state": OPEN, "failure_count": 5}),
            ("circuit-breaker-google-headless.json", {"provider": "google", "auth_type": "headless", "state": CLOSED, "failure_count": 0}),
            ("circuit-breaker-bedrock-aws_iam.json", {"provider": "bedrock", "auth_type": "aws_iam", "state": CLOSED, "failure_count": 0}),
        ]:
            (tmp_path / fname).write_text(json.dumps(payload))
        result = list_buckets(str(tmp_path))
        assert set(result.keys()) == {"google", "bedrock"}
        assert set(result["google"].keys()) == {"http_api", "headless"}
        assert result["google"]["http_api"]["state"] == OPEN
        assert result["google"]["headless"]["state"] == CLOSED

    def test_excludes_transitional_symlink(self, tmp_path):
        target = tmp_path / "circuit-breaker-google-http_api.json"
        target.write_text(json.dumps({
            "provider": "google", "auth_type": "http_api",
            "state": CLOSED, "failure_count": 0,
        }))
        os.symlink("circuit-breaker-google-http_api.json",
                   str(tmp_path / "circuit-breaker-google.json"))
        result = list_buckets(str(tmp_path))
        assert "google" in result
        # No "google" → legacy-shape entry; only the http_api bucket surfaces.
        assert list(result["google"].keys()) == ["http_api"]

    def test_handles_corrupted_file(self, tmp_path):
        (tmp_path / "circuit-breaker-openai-headless.json").write_text("{{")
        result = list_buckets(str(tmp_path))
        # Corrupted → default CLOSED surfacing.
        assert result["openai"]["headless"]["state"] == CLOSED


# ---------------------------------------------------------------------------
# cleanup_stale_files / cleanup_stale_tempfiles
# ---------------------------------------------------------------------------


class TestCleanupStaleFiles:
    def test_removes_old_files(self, tmp_path):
        old_file = tmp_path / "circuit-breaker-old-headless.json"
        old_file.write_text("{}")
        old_time = time.time() - (48 * 3600)
        os.utime(old_file, (old_time, old_time))

        new_file = tmp_path / "circuit-breaker-new-headless.json"
        new_file.write_text("{}")

        removed = cleanup_stale_files(str(tmp_path), max_age_hours=24)
        assert removed == 1
        assert not old_file.exists()
        assert new_file.exists()

    def test_preserves_transitional_symlink(self, tmp_path):
        target = tmp_path / "circuit-breaker-google-http_api.json"
        target.write_text("{}")
        symlink = tmp_path / "circuit-breaker-google.json"
        os.symlink("circuit-breaker-google-http_api.json", str(symlink))
        # Age both far past the threshold.
        old_time = time.time() - (48 * 3600)
        os.utime(target, (old_time, old_time))

        removed = cleanup_stale_files(str(tmp_path), max_age_hours=24)
        assert removed == 1
        # Symlink preserved unconditionally.
        assert symlink.is_symlink()

    def test_ignores_non_cb_files(self, tmp_path):
        other = tmp_path / "something-else.json"
        other.write_text("{}")
        old_time = time.time() - (48 * 3600)
        os.utime(other, (old_time, old_time))
        assert cleanup_stale_files(str(tmp_path), max_age_hours=24) == 0
        assert other.exists()


class TestCleanupStaleTempfiles:
    """T1.3 C8 closure — startup tempfile janitor."""

    def test_removes_old_tmp_redaction(self, tmp_path):
        f = tmp_path / "tmp-redaction-abc"
        f.write_text("x")
        os.utime(f, (time.time() - 7200, time.time() - 7200))  # 2h old
        removed = cleanup_stale_tempfiles(str(tmp_path), max_age_seconds=3600)
        assert removed == 1
        assert not f.exists()

    def test_keeps_recent_tmp_redaction(self, tmp_path):
        f = tmp_path / "tmp-redaction-xyz"
        f.write_text("x")
        removed = cleanup_stale_tempfiles(str(tmp_path), max_age_seconds=3600)
        assert removed == 0
        assert f.exists()

    def test_ignores_directories(self, tmp_path):
        d = tmp_path / "tmp-redaction-dir"
        d.mkdir()
        os.utime(d, (time.time() - 7200, time.time() - 7200))
        removed = cleanup_stale_tempfiles(str(tmp_path), max_age_seconds=3600)
        assert removed == 0
        assert d.is_dir()

    def test_nonexistent_dir(self, tmp_path):
        assert cleanup_stale_tempfiles(str(tmp_path / "no-such")) == 0
