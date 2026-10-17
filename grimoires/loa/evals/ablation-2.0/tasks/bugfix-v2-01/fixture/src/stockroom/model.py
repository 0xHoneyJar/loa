"""The item model and the errors of the stockroom package."""
from dataclasses import dataclass


class StockError(Exception):
    """Base class of every stockroom error."""


class UnknownSku(StockError, KeyError):
    def __init__(self, sku):
        super().__init__(sku)
        self.sku = sku

    def __str__(self):
        return f"unknown sku: {self.sku}"


class DuplicateSku(StockError, ValueError):
    def __init__(self, sku):
        super().__init__(f"duplicate sku: {sku}")
        self.sku = sku


class DuplicateName(StockError, ValueError):
    def __init__(self, name):
        super().__init__(f"duplicate name: {name}")
        self.name = name


class InvalidItem(StockError, ValueError):
    """An item field, or a change to one, is not acceptable."""


@dataclass(frozen=True)
class Item:
    """One stock-keeping unit. Tags are stored case-folded."""

    sku: str
    name: str
    category: str
    qty: int = 0
    tags: frozenset = frozenset()

    def __post_init__(self):
        if not isinstance(self.sku, str) or not self.sku or self.sku != self.sku.strip() or " " in self.sku:
            raise InvalidItem(f"bad sku: {self.sku!r}")
        if not isinstance(self.name, str) or not self.name.strip():
            raise InvalidItem(f"bad name: {self.name!r}")
        if not isinstance(self.category, str) or not self.category.strip():
            raise InvalidItem(f"bad category: {self.category!r}")
        if not isinstance(self.qty, int) or isinstance(self.qty, bool) or self.qty < 0:
            raise InvalidItem(f"bad qty: {self.qty!r}")
        if isinstance(self.tags, str):
            raise InvalidItem("tags must be a collection of strings")
        object.__setattr__(self, "tags", frozenset(str(t).casefold() for t in self.tags))

    @property
    def key(self):
        """The name as names are compared: stripped and case-folded."""
        return self.name.strip().casefold()
