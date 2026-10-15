"""An in-memory ledger: create and update entries."""
import datetime
import re

from .errors import RecordError

_CURRENCY = re.compile(r"\A[A-Z]{3}\Z")


def _check(payload) -> None:
    if not isinstance(payload, dict):
        raise RecordError("record must be a mapping")
    for name in ("id", "amount", "currency", "date"):
        if name not in payload:
            raise RecordError(f"missing field: {name}")
    if not isinstance(payload["id"], str) or not payload["id"].strip():
        raise RecordError("id must be a non-empty string")
    value = payload["amount"]
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        raise RecordError("amount must be a non-negative number")
    if not isinstance(payload["currency"], str) or not _CURRENCY.match(payload["currency"]):
        raise RecordError("currency must be a three-letter ISO code")
    try:
        datetime.date.fromisoformat(payload["date"])
    except (TypeError, ValueError):
        raise RecordError("date must be an ISO date (YYYY-MM-DD)") from None


def create_entry(ledger: list, payload: dict) -> dict:
    """Validate ``payload`` and append a copy; ids are unique within the ledger."""
    _check(payload)
    if any(e["id"] == payload["id"] for e in ledger):
        raise RecordError(f"duplicate id: {payload['id']}")
    entry = dict(payload)
    ledger.append(entry)
    return entry


def update_entry(ledger: list, entry_id: str, changes: dict) -> dict:
    """Apply ``changes`` to the entry ``entry_id``; the result must still be a valid record."""
    for i, e in enumerate(ledger):
        if e["id"] == entry_id:
            merged = {**e, **changes}
            if merged["id"] != entry_id:
                raise RecordError("id cannot change")
            _check(merged)
            ledger[i] = merged
            return merged
    raise RecordError(f"no such entry: {entry_id}")
