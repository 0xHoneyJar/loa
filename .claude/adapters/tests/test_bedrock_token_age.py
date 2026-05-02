"""Tests for Bedrock token age sentinel + rotation reminders (NFR-Sec11).

Covers:

* Sentinel write/read roundtrip with hint-only persistence (no raw token)
* First-seen vs last-seen update semantics
* Token rotation detection via hint mismatch
* Graduated stderr warnings at day-60 / day-80 / day-90 thresholds
* In-process latches (info notice one-shot, tier-2 every-100, tier-3 every-call)
* Token hint is last-4 of SHA256 (deterministic, non-reversible)
* Sentinel is best-effort — failures don't break the request path
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers.bedrock_token_age import (  # noqa: E402
    _force_test_state,
    _hash_hint,
    _read_sentinel,
    _sentinel_path,
    record_token_use,
)


_FAKE_TOKEN = "ABSKRTOKEN" + "A" * 80
_FAKE_TOKEN_2 = "ABSKRROTATED" + "B" * 80


@pytest.fixture(autouse=True)
def _isolate_state(monkeypatch, tmp_path):
    """Each test gets a fresh sentinel file + reset in-process state."""
    monkeypatch.setenv("LOA_CACHE_DIR", str(tmp_path))
    _force_test_state()
    yield
    _force_test_state()


# ---------------------------------------------------------------------------
# Hint computation: deterministic, non-reversible
# ---------------------------------------------------------------------------


def test_hash_hint_is_deterministic():
    assert _hash_hint("abc") == _hash_hint("abc")


def test_hash_hint_is_short_hex():
    h = _hash_hint(_FAKE_TOKEN)
    assert len(h) == 4
    assert all(c in "0123456789abcdef" for c in h)


def test_hash_hint_does_not_leak_token():
    """Even a short hint should NOT contain any substring of the token."""
    token = _FAKE_TOKEN
    hint = _hash_hint(token)
    # Token cannot be in hint (length 4 makes this trivially true, but assert
    # to make the property explicit).
    assert token not in hint
    # Common token prefixes shouldn't appear in hint either.
    assert "ABSK" not in hint.upper()


def test_hash_hint_differs_for_different_tokens():
    a = _hash_hint(_FAKE_TOKEN)
    b = _hash_hint(_FAKE_TOKEN_2)
    assert a != b


def test_hash_hint_empty_returns_empty():
    assert _hash_hint("") == ""


# ---------------------------------------------------------------------------
# Sentinel: first call writes; subsequent calls update last_seen
# ---------------------------------------------------------------------------


def test_first_call_writes_sentinel_with_first_seen_and_last_seen(tmp_path):
    record_token_use(_FAKE_TOKEN)
    sentinel = _read_sentinel(_sentinel_path())
    assert sentinel is not None
    assert sentinel["token_hint"] == _hash_hint(_FAKE_TOKEN)
    assert "first_seen" in sentinel
    assert "last_seen" in sentinel
    assert sentinel["first_seen"] == sentinel["last_seen"]
    # Token NEVER persisted.
    assert _FAKE_TOKEN not in json.dumps(sentinel)


def test_second_call_updates_last_seen_but_not_first_seen(tmp_path):
    record_token_use(_FAKE_TOKEN)
    first = _read_sentinel(_sentinel_path())
    assert first is not None

    record_token_use(_FAKE_TOKEN)
    second = _read_sentinel(_sentinel_path())

    assert second["first_seen"] == first["first_seen"]


def test_token_rotation_writes_new_sentinel_entry(tmp_path):
    """When the env-var token changes, the sentinel records the new hint."""
    record_token_use(_FAKE_TOKEN)
    record_token_use(_FAKE_TOKEN_2)

    sentinel = _read_sentinel(_sentinel_path())
    assert sentinel["token_hint"] == _hash_hint(_FAKE_TOKEN_2)
    # Original token's hint is no longer the active one.
    assert sentinel["token_hint"] != _hash_hint(_FAKE_TOKEN)


def test_empty_token_is_no_op(tmp_path):
    record_token_use("")
    assert not _sentinel_path().exists()


# ---------------------------------------------------------------------------
# Graduated warnings — day-60 / day-80 / day-90 thresholds
# ---------------------------------------------------------------------------


def _seed_aged_sentinel(tmp_path: Path, age_days: int, hint: str) -> None:
    """Plant a sentinel claiming the token was first seen N days ago."""
    first_seen = datetime.now(timezone.utc) - timedelta(days=age_days)
    sentinel_path = tmp_path / "bedrock-token-age.json"
    sentinel_path.write_text(json.dumps({
        "token_hint": hint,
        "first_seen": first_seen.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "last_seen": first_seen.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }))


def test_age_below_60_days_silent(tmp_path, capsys):
    hint = _hash_hint(_FAKE_TOKEN)
    _seed_aged_sentinel(tmp_path, age_days=30, hint=hint)
    record_token_use(_FAKE_TOKEN)
    captured = capsys.readouterr()
    assert captured.err == ""


def test_age_60_to_80_emits_one_shot_info_notice(tmp_path, capsys):
    hint = _hash_hint(_FAKE_TOKEN)
    _seed_aged_sentinel(tmp_path, age_days=65, hint=hint)

    record_token_use(_FAKE_TOKEN)
    first_call = capsys.readouterr()
    assert "Rotation recommended" in first_call.err

    # Second call within same process — silent (one-shot latch).
    record_token_use(_FAKE_TOKEN)
    second_call = capsys.readouterr()
    assert second_call.err == ""


def test_age_80_to_90_warns_every_100_requests(tmp_path, capsys):
    hint = _hash_hint(_FAKE_TOKEN)
    _seed_aged_sentinel(tmp_path, age_days=85, hint=hint)

    # First call: warning.
    record_token_use(_FAKE_TOKEN)
    first = capsys.readouterr()
    assert "WARN" in first.err
    assert "Rotation overdue" in first.err

    # Calls 2..100: silent (counter mod 100).
    for _ in range(99):
        record_token_use(_FAKE_TOKEN)
    intermediate = capsys.readouterr()
    assert intermediate.err == ""

    # Call 101: another warning.
    record_token_use(_FAKE_TOKEN)
    after = capsys.readouterr()
    assert "WARN" in after.err


def test_age_at_or_above_90_warns_every_call(tmp_path, capsys):
    hint = _hash_hint(_FAKE_TOKEN)
    _seed_aged_sentinel(tmp_path, age_days=120, hint=hint)

    for _ in range(3):
        record_token_use(_FAKE_TOKEN)
    captured = capsys.readouterr()
    # 3 warnings (one per call).
    assert captured.err.count("exceeds") >= 3 or captured.err.count("rotation cadence") >= 3


def test_configurable_max_age_days(tmp_path, capsys):
    """Operator can set token_max_age_days=30 and get aggressive rotation."""
    hint = _hash_hint(_FAKE_TOKEN)
    _seed_aged_sentinel(tmp_path, age_days=25, hint=hint)
    # With max_age_days=30, day 25 is in tier-1 (60..80% of 30 = 20..26.7).
    record_token_use(_FAKE_TOKEN, max_age_days=30)
    captured = capsys.readouterr()
    assert "Rotation recommended" in captured.err


# ---------------------------------------------------------------------------
# Token rotation resets in-process latches
# ---------------------------------------------------------------------------


def test_rotation_resets_info_notice_latch(tmp_path, capsys):
    hint_a = _hash_hint(_FAKE_TOKEN)
    _seed_aged_sentinel(tmp_path, age_days=65, hint=hint_a)

    # First call with token A — info notice fires once.
    record_token_use(_FAKE_TOKEN)
    capsys.readouterr()  # discard

    # Second call with same token — silent (latch holds).
    record_token_use(_FAKE_TOKEN)
    silent = capsys.readouterr()
    assert silent.err == ""

    # ROTATION: third call with token B — sentinel reset, latch reset.
    record_token_use(_FAKE_TOKEN_2)
    rotation = capsys.readouterr()
    # New token has no aged sentinel, so silent on first call.
    assert rotation.err == ""


# ---------------------------------------------------------------------------
# Sentinel best-effort failure mode
# ---------------------------------------------------------------------------


def test_sentinel_write_failure_is_non_fatal(tmp_path):
    """A read-only LOA_CACHE_DIR shouldn't break record_token_use."""
    # Make the cache dir read-only after first call so subsequent writes fail.
    record_token_use(_FAKE_TOKEN)  # creates sentinel
    sentinel = _sentinel_path()
    sentinel.chmod(0o400)
    try:
        # Should not raise even if write fails.
        record_token_use(_FAKE_TOKEN)
    finally:
        sentinel.chmod(0o600)


def test_sentinel_read_corrupt_returns_none(tmp_path):
    sentinel = _sentinel_path()
    sentinel.parent.mkdir(parents=True, exist_ok=True)
    sentinel.write_text("not valid json {")
    # _read_sentinel should return None and record_token_use should treat as
    # first-sighting (write a new entry).
    assert _read_sentinel(sentinel) is None
    record_token_use(_FAKE_TOKEN)
    # After the call, sentinel should be valid JSON.
    new_sentinel = _read_sentinel(sentinel)
    assert new_sentinel is not None
    assert new_sentinel["token_hint"] == _hash_hint(_FAKE_TOKEN)


# ---------------------------------------------------------------------------
# Sentinel content does NOT leak the raw token
# ---------------------------------------------------------------------------


def test_sentinel_content_redacts_raw_token(tmp_path):
    record_token_use(_FAKE_TOKEN)
    sentinel = _sentinel_path()
    body = sentinel.read_text()
    # Sentinel contains the hint but NEVER the full token.
    assert _FAKE_TOKEN not in body
    assert _hash_hint(_FAKE_TOKEN) in body
