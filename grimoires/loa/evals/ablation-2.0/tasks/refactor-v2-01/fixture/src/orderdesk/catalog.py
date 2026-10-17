"""The product catalog: SKU -> product (name, unit price in cents)."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Product:
    sku: str
    name: str
    price_cents: int


class Catalog:
    """An in-memory catalog; SKUs are unique."""

    def __init__(self, products=()):
        self._items = {}
        for product in products:
            self.add(product)

    def add(self, product):
        if product.sku in self._items:
            raise ValueError(f"duplicate sku: {product.sku!r}")
        self._items[product.sku] = product

    def get(self, sku):
        try:
            return self._items[sku]
        except KeyError:
            raise KeyError(f"unknown sku: {sku!r}") from None

    def __contains__(self, sku):
        return sku in self._items

    def skus(self):
        return sorted(self._items)
