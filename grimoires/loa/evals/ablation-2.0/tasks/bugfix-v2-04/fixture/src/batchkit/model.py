"""Items and errors."""
from dataclasses import dataclass


class BatchkitError(Exception):
    """Base class of every batchkit error."""


class ResourceBusy(BatchkitError):
    def __init__(self, name, holder):
        super().__init__(f"resource {name} is locked by {holder}")
        self.name = name
        self.holder = holder


class NotHeld(BatchkitError):
    def __init__(self, name, owner):
        super().__init__(f"resource {name} is not locked by {owner}")
        self.name = name
        self.owner = owner


class LedgerError(BatchkitError):
    """The ledger refused a change."""


class Overdraft(LedgerError):
    def __init__(self, account, balance, amount):
        super().__init__(f"overdraft on {account}: balance {balance}, change {amount}")
        self.account = account


class UnknownAccount(LedgerError):
    def __init__(self, account):
        super().__init__(f"unknown account: {account}")
        self.account = account


@dataclass(frozen=True)
class Item:
    """One change: add ``amount`` (may be negative) to ``account``."""

    id: str
    account: str
    amount: int

    def __post_init__(self):
        if not isinstance(self.id, str) or not self.id:
            raise ValueError("item id must be a non-empty string")
        if isinstance(self.amount, bool) or not isinstance(self.amount, int):
            raise TypeError("item amount must be an int")
