"""Price quotes with volume discounts; a bulk quote allows larger quantities."""
import re

_PATTERN = r"[A-Z]{3}-[0-9]{4}"
STANDARD_LIMIT = 999
BULK_LIMIT = 9999
DISCOUNT_STEPS = ((1000, 15), (100, 10), (10, 5))


def _line_ok(sku, qty, limit):
    if not isinstance(sku, str) or not re.fullmatch(_PATTERN, sku):
        return "sku"
    if isinstance(qty, bool) or not isinstance(qty, int) or qty < 1 or qty > limit:
        return "qty"
    return None


def _discount(qty):
    for threshold, pct in DISCOUNT_STEPS:
        if qty >= threshold:
            return pct
    return 0


def _row(catalog, sku, qty):
    pct = _discount(qty)
    unit = catalog.get(sku).price_cents
    return {"sku": sku, "qty": qty, "discount_pct": pct, "cents": unit * qty * (100 - pct) // 100}


def quote(catalog, lines):
    """A quote for ``lines``; each line is discounted by its own quantity."""
    rows = []
    for sku, qty in lines:
        problem = _line_ok(sku, qty, STANDARD_LIMIT)
        if problem == "sku":
            raise ValueError(f"invalid sku: {sku!r}")
        if problem == "qty":
            raise ValueError(f"invalid quantity for {sku}: {qty!r}")
        rows.append(_row(catalog, sku, qty))
    return {"rows": rows, "total_cents": sum(row["cents"] for row in rows)}


def bulk_quote(catalog, lines):
    """Like ``quote`` but for quantities up to the bulk limit."""
    rows = []
    for sku, qty in lines:
        problem = _line_ok(sku, qty, BULK_LIMIT)
        if problem is not None:
            if problem == "sku":
                raise ValueError(f"invalid sku: {sku!r}")
            raise ValueError(f"invalid quantity for {sku}: {qty!r}")
        rows.append(_row(catalog, sku, qty))
    return {"rows": rows, "total_cents": sum(row["cents"] for row in rows), "bulk": True}
