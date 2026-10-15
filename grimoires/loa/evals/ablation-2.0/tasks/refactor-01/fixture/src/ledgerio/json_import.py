"""Ledger entries from a JSON array of objects."""
import datetime
import json
import re

from .errors import RecordError


def read_json(text: str) -> list:
    """Every array item as a validated record; a bad item raises ``RecordError`` naming its index."""
    data = json.loads(text)
    if not isinstance(data, list):
        raise RecordError("top level must be an array")
    out = []
    for i, item in enumerate(data):
        try:
            if not isinstance(item, dict):
                raise RecordError("record must be a mapping")
            for field in ("id", "amount", "currency", "date"):
                if field not in item:
                    raise RecordError(f"missing field: {field}")
            if not isinstance(item["id"], str) or not item["id"].strip():
                raise RecordError("id must be a non-empty string")
            amount = item["amount"]
            if isinstance(amount, bool) or not isinstance(amount, (int, float)) or amount < 0:
                raise RecordError("amount must be a non-negative number")
            if not isinstance(item["currency"], str) or not re.fullmatch(r"[A-Z]{3}", item["currency"]):
                raise RecordError("currency must be a three-letter ISO code")
            try:
                datetime.date.fromisoformat(item["date"])
            except (TypeError, ValueError):
                raise RecordError("date must be an ISO date (YYYY-MM-DD)") from None
        except RecordError as e:
            raise RecordError(f"item {i}: {e}") from None
        out.append(dict(item))
    return out
