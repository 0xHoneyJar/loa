"""Running a batch of items."""
from .model import LedgerError
from .report import Report
from .worker import apply_item


def run_batch(pool, ledger, journal, items, owner="batch"):
    """Apply ``items`` in order while holding every account they touch.

    Returns a ``Report``.  A refused item ends the batch.
    """
    items = list(items)
    report = Report()
    accounts = sorted({item.account for item in items})
    for account in accounts:
        pool.acquire(account, owner)
    for item in items:
        try:
            outcome = apply_item(ledger, journal, item)
        except LedgerError as exc:
            report.fail(item.id, str(exc))
            return report
        report.note(item.id, outcome)
    for item_id in report.applied:
        journal.record(item_id)
    for account in accounts:
        pool.release(account, owner)
    return report
