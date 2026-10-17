"""The collection of live items, keyed by sku."""
from contextlib import contextmanager

from .model import UnknownSku


class Store:
    """Live items keyed by sku.

    ``revision`` counts the changes made to the collection. Inside a
    ``batch()`` block the changes are grouped: ``revision`` advances once,
    when the outermost block ends, if anything in the block changed.
    """

    def __init__(self):
        self._items = {}
        self.revision = 0
        self._depth = 0
        self._pending = False

    def __len__(self):
        return len(self._items)

    def __contains__(self, sku):
        return sku in self._items

    def get(self, sku):
        try:
            return self._items[sku]
        except KeyError:
            raise UnknownSku(sku) from None

    def items(self):
        return [self._items[sku] for sku in sorted(self._items)]

    def put(self, item):
        self._items[item.sku] = item
        self._changed()

    def pop(self, sku):
        """Take an item out of the collection and return it.

        Callers that put a changed item back report the change once, through
        ``put``, so a pop on its own does not count as a change.
        """
        item = self.get(sku)
        del self._items[sku]
        return item

    def _changed(self):
        if self._depth:
            self._pending = True
        else:
            self.revision += 1

    @contextmanager
    def batch(self):
        self._depth += 1
        try:
            yield self
        finally:
            self._depth -= 1
            if self._depth == 0 and self._pending:
                self._pending = False
                self.revision += 1
