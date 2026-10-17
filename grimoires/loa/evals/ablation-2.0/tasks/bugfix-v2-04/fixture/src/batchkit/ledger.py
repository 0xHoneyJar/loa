"""Account balances."""
from .model import Overdraft, UnknownAccount


class Ledger:
    """Integer balances by account name; a balance never goes below zero."""

    def __init__(self, balances=None):
        self._balances = dict(balances or {})

    def accounts(self):
        return sorted(self._balances)

    def balance(self, account):
        try:
            return self._balances[account]
        except KeyError:
            raise UnknownAccount(account) from None

    def apply(self, account, amount):
        """Add ``amount`` to ``account``; return the new balance."""
        current = self.balance(account)
        if current + amount < 0:
            raise Overdraft(account, current, amount)
        self._balances[account] = current + amount
        return self._balances[account]

    def balances(self):
        """A copy of every balance."""
        return dict(self._balances)
