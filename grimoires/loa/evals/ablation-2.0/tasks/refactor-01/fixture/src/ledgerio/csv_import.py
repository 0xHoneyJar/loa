"""Ledger entries from CSV text (header row: id,amount,currency,date)."""
import csv
import datetime
import io
import re

from .errors import RecordError

_CCY = re.compile(r"[A-Z]{3}")


def _validate_row(row: dict) -> None:
    if not isinstance(row, dict):
        raise RecordError("record must be a mapping")
    for field in ("id", "amount", "currency", "date"):
        if field not in row:
            raise RecordError(f"missing field: {field}")
    if not isinstance(row["id"], str) or not row["id"].strip():
        raise RecordError("id must be a non-empty string")
    amount = row["amount"]
    if isinstance(amount, bool) or not isinstance(amount, (int, float)) or amount < 0:
        raise RecordError("amount must be a non-negative number")
    if not isinstance(row["currency"], str) or not _CCY.fullmatch(row["currency"]):
        raise RecordError("currency must be a three-letter ISO code")
    try:
        datetime.date.fromisoformat(row["date"])
    except (TypeError, ValueError):
        raise RecordError("date must be an ISO date (YYYY-MM-DD)") from None


def _number(text: str):
    try:
        return int(text)
    except ValueError:
        try:
            return float(text)
        except ValueError:
            return text


def read_csv(text: str) -> list:
    """Every data row as a validated record; a bad row raises ``RecordError`` naming its line."""
    out = []
    reader = csv.DictReader(io.StringIO(text))
    for lineno, row in enumerate(reader, start=2):
        rec = {k.strip(): (v or "").strip() for k, v in row.items() if k is not None}
        if "amount" in rec:
            rec["amount"] = _number(rec["amount"])
        try:
            _validate_row(rec)
        except RecordError as e:
            raise RecordError(f"line {lineno}: {e}") from None
        out.append(rec)
    return out
