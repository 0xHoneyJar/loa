"""The inventory facade: operations and lookups over one store."""
from dataclasses import replace

from . import report
from .index import Index
from .model import DuplicateName, DuplicateSku, InvalidItem
from .stats import Summary
from .store import Store
from .trash import Trash


class Inventory:
    def __init__(self):
        self.store = Store()
        self.index = Index(self.store)
        self.summary = Summary(self.store)
        self.trash = Trash()

    @property
    def revision(self):
        return self.store.revision

    def batch(self):
        return self.store.batch()

    # -- operations -------------------------------------------------------
    def _check_free(self, item):
        if item.sku in self.store:
            raise DuplicateSku(item.sku)
        if self.index.find(item.name) is not None:
            raise DuplicateName(item.name)

    def add(self, item):
        self._check_free(item)
        self.store.put(item)
        return item

    def remove(self, sku):
        item = self.store.pop(sku)
        self.trash.add(item)
        return item

    def move(self, sku, category):
        moved = replace(self.store.get(sku), category=category)
        self.store.pop(sku)
        self.store.put(moved)
        return moved

    def restock(self, sku, delta):
        item = self.store.get(sku)
        qty = item.qty + delta
        if qty < 0:
            raise InvalidItem(f"qty below zero: {sku}")
        restocked = replace(item, qty=qty)
        self.store.pop(sku)
        self.store.put(restocked)
        return restocked

    def restore(self, sku):
        item = self.trash.peek(sku)
        self._check_free(item)
        self.trash.take(sku)
        self.store.put(item)
        return item

    # -- lookups ----------------------------------------------------------
    def find(self, name):
        return self.index.find(name)

    def with_tag(self, tag):
        return self.index.with_tag(tag)

    def counts(self):
        return self.summary.counts()

    def total_qty(self):
        return self.summary.total_qty()

    def items(self):
        return self.store.items()

    def listing(self):
        return report.listing(self.items())

    def table(self):
        return report.category_table(self.counts())
