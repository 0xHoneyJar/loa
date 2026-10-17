"""Applying one item."""

APPLIED = "applied"
SKIPPED = "skipped"


def apply_item(ledger, journal, item):
    """Apply ``item`` unless the journal already has its id.

    Returns ``"applied"`` or ``"skipped"``; a refused change raises the
    ledger's error.
    """
    if journal.seen(item.id):
        return SKIPPED
    ledger.apply(item.account, item.amount)
    return APPLIED
