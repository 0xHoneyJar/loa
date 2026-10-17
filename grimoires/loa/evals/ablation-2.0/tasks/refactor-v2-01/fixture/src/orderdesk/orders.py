"""Customer orders: lines priced against the catalog."""
import re

MAX_QTY = 999
_SKU_RE = re.compile(r"[A-Z]{3}-[0-9]{4}")


def _valid_line(sku, qty):
    if not isinstance(sku, str) or _SKU_RE.fullmatch(sku) is None:
        raise ValueError(f"invalid sku: {sku!r}")
    if isinstance(qty, bool) or not isinstance(qty, int) or not 1 <= qty <= MAX_QTY:
        raise ValueError(f"invalid quantity for {sku}: {qty!r}")
    return sku, qty


def place_order(catalog, lines):
    """An order for ``lines`` [(sku, qty), ...]; the quantities of a repeated SKU add up."""
    merged = {}
    for sku, qty in lines:
        sku, qty = _valid_line(sku, qty)
        catalog.get(sku)
        merged[sku] = merged.get(sku, 0) + qty
    if not merged:
        raise ValueError("an order needs at least one line")
    items = [
        {"sku": sku, "qty": qty, "cents": catalog.get(sku).price_cents * qty}
        for sku, qty in sorted(merged.items())
    ]
    return {"items": items, "total_cents": sum(item["cents"] for item in items)}


def order_total(catalog, lines):
    """The total in cents of ``lines`` without building an order."""
    total = 0
    for sku, qty in lines:
        if not isinstance(sku, str) or not _SKU_RE.fullmatch(sku):
            raise ValueError(f"invalid sku: {sku!r}")
        if isinstance(qty, bool) or not isinstance(qty, int) or qty < 1 or qty > MAX_QTY:
            raise ValueError(f"invalid quantity for {sku}: {qty!r}")
        total += catalog.get(sku).price_cents * qty
    return total
