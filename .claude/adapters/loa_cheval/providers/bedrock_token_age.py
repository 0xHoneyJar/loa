"""Bedrock token age sentinel + rotation reminders (cycle-096 / NFR-Sec11).

Tracks how long the maintainer's Bedrock API key has been in use and emits
graduated stderr warnings as it approaches the recommended 90-day rotation
cadence (NFR-Sec6). Sentinel file persists across process restarts so the
"first seen" timestamp is durable.

Sentinel schema (``$LOA_CACHE_DIR/bedrock-token-age.json``)::

    {
        "token_hint": "abcd",           # last-4 of SHA256(token); NEVER full token
        "first_seen": "2026-05-02T...",
        "last_seen":  "2026-05-02T..."
    }

Warning thresholds (configurable via ``hounfour.bedrock.token_max_age_days``,
default 90):

* Days 0..60: silent
* Days 60..80: ONE stderr info notice per process ("rotation recommended")
* Days 80..90: stderr warning every 100 requests
* Days 90+: stderr warning every call ("rotation overdue")

Token rotation (env var change) is detected by hint mismatch; the adapter
writes a new sentinel entry and resets the in-process notice latch.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

logger = logging.getLogger("loa_cheval.providers.bedrock_token_age")


_SENTINEL_FILENAME = "bedrock-token-age.json"
_DEFAULT_MAX_AGE_DAYS = 90


def _hash_hint(token: str) -> str:
    """Return the last 4 hex chars of SHA256(token).

    Designed to be a stable but non-reversible identifier — suitable for
    audit logs and rotation-detection. NEVER returns or logs the raw token.
    """
    if not token:
        return ""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()[:4]


def _sentinel_path() -> Path:
    """Resolve the sentinel path; honors LOA_CACHE_DIR (default ``.run``)."""
    cache_dir = os.environ.get("LOA_CACHE_DIR") or ".run"
    return Path(cache_dir) / _SENTINEL_FILENAME


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_iso(value: str) -> Optional[datetime]:
    """Parse a UTC ISO8601 string. Returns None on malformed input."""
    if not isinstance(value, str) or not value:
        return None
    try:
        # Strip optional 'Z' and parse as naive UTC.
        s = value[:-1] if value.endswith("Z") else value
        return datetime.fromisoformat(s).replace(tzinfo=timezone.utc)
    except (ValueError, TypeError):
        return None


def _read_sentinel(path: Path) -> Optional[dict]:
    """Read sentinel file; return None on missing/malformed."""
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    return data


def _write_sentinel(path: Path, payload: dict) -> None:
    """Best-effort sentinel write. Failures are non-fatal — token-age tracking
    is operator visibility, not security gating."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    except OSError:
        pass


# Per-process state. Reset on token rotation.
_in_process_state = {
    "current_hint": None,    # type: Optional[str]
    "info_notice_emitted": False,  # day-60..80 latch
    "request_counter": 0,    # day-80..90 cadence
}


def _reset_in_process_state(new_hint: str) -> None:
    """Called when the env-var token has rotated mid-process."""
    _in_process_state["current_hint"] = new_hint
    _in_process_state["info_notice_emitted"] = False
    _in_process_state["request_counter"] = 0


def record_token_use(token: str, *, max_age_days: int = _DEFAULT_MAX_AGE_DAYS) -> None:
    """Record a Bedrock token use; emit graduated stderr warnings as appropriate.

    Call this on every Bedrock request from the adapter. Cheap on the happy
    path: 1 hash, 1 sentinel read on first call per process, 1 sentinel
    write on rotation or first-seen. The sentinel is best-effort — failures
    do not prevent the request.

    Args:
        token: The resolved Bearer token. NEVER persisted in the sentinel.
        max_age_days: Configurable rotation reminder cadence (default 90).
    """
    if not token:
        return  # No token, nothing to track.

    hint = _hash_hint(token)
    sentinel_path = _sentinel_path()
    now = _now_iso()

    # Detect token rotation: in-process hint mismatch.
    prior_hint = _in_process_state["current_hint"]
    if prior_hint is not None and prior_hint != hint:
        _reset_in_process_state(hint)
    elif prior_hint is None:
        _in_process_state["current_hint"] = hint

    # Read existing sentinel (if any).
    existing = _read_sentinel(sentinel_path)

    if existing is None or existing.get("token_hint") != hint:
        # First sighting of this token (in this filesystem) — write a fresh entry.
        _write_sentinel(
            sentinel_path,
            {"token_hint": hint, "first_seen": now, "last_seen": now},
        )
        return

    # Update last_seen on every call.
    existing["last_seen"] = now
    _write_sentinel(sentinel_path, existing)

    # Compute age in days.
    first_seen_dt = _parse_iso(existing.get("first_seen", ""))
    if first_seen_dt is None:
        return
    age_days = (datetime.now(timezone.utc) - first_seen_dt).days

    _emit_age_warning(hint, age_days, max_age_days)


def _emit_age_warning(hint: str, age_days: int, max_age_days: int) -> None:
    """Graduated stderr notice based on age.

    Tier 1 (60..80% of max_age): one-shot info notice per process
    Tier 2 (80..100% of max_age): warning every 100 requests
    Tier 3 (>= max_age): warning every call
    """
    tier1_start = int(max_age_days * 0.667)  # day 60 default
    tier2_start = int(max_age_days * 0.889)  # day 80 default

    if age_days < tier1_start:
        return  # silent

    if age_days < tier2_start:
        # Tier 1: one-shot per process.
        if _in_process_state["info_notice_emitted"]:
            return
        sys.stderr.write(
            f"[loa-cheval] Bedrock token age: {age_days} days (hint: ...{hint}). "
            f"Rotation recommended at {max_age_days} days. AWS Console → Bedrock → "
            f"API keys → revoke and reissue.\n"
        )
        _in_process_state["info_notice_emitted"] = True
        return

    if age_days < max_age_days:
        # Tier 2: warning every 100 requests.
        _in_process_state["request_counter"] += 1
        if _in_process_state["request_counter"] % 100 != 1:
            return  # only on the 1st, 101st, 201st, etc.
        sys.stderr.write(
            f"[loa-cheval] WARN: Bedrock token age: {age_days} days (hint: ...{hint}). "
            f"Rotation overdue is {max_age_days - age_days} days from now. "
            f"Loa will surface as warning at every call after day {max_age_days}.\n"
        )
        return

    # Tier 3: every call.
    sys.stderr.write(
        f"[loa-cheval] WARN: Bedrock token age: {age_days} days (hint: ...{hint}), "
        f"exceeds {max_age_days}-day rotation cadence. Rotate via AWS console; "
        f"Loa continues to operate but operator action is overdue (NFR-Sec11).\n"
    )


# --- Helpers exported for unit tests ---


def _force_test_state(*, hint=None, info_notice_emitted=False, request_counter=0) -> None:
    """Reset in-process state — TEST ONLY."""
    _in_process_state["current_hint"] = hint
    _in_process_state["info_notice_emitted"] = info_notice_emitted
    _in_process_state["request_counter"] = request_counter
