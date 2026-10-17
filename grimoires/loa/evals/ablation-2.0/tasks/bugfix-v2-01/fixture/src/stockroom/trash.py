"""Removed items, kept so they can be restored."""
from .model import UnknownSku


class Trash:
    """The most recently removed item of each sku."""

    def __init__(self):
        self._items = {}

    def __len__(self):
        return len(self._items)

    def __contains__(self, sku):
        return sku in self._items

    def add(self, item):
        self._items[item.sku] = item

    def peek(self, sku):
        try:
            return self._items[sku]
        except KeyError:
            raise UnknownSku(sku) from None

    def take(self, sku):
        item = self.peek(sku)
        del self._items[sku]
        return item

    def skus(self):
        return sorted(self._items)
