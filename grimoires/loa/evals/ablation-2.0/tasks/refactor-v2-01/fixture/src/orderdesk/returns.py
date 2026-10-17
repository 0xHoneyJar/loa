"""Returns against a placed order; SKUs are accepted in any case and with stray spaces."""
import re

SKU_PATTERN = re.compile(r"[A-Z]{3}-[0-9]{4}")
LIMIT = 999


def return_items(order, lines):
    """The cleaned return lines for ``lines`` against ``order`` (from ``orders.place_order``)."""
    ordered = {item["sku"]: item["qty"] for item in order["items"]}
    out = []
    for raw_sku, qty in lines:
        sku = raw_sku.strip().upper() if isinstance(raw_sku, str) else raw_sku
        if not isinstance(sku, str) or not SKU_PATTERN.fullmatch(sku):
            raise ValueError(f"invalid sku: {sku!r}")
        if type(qty) is bool or not isinstance(qty, int):
            raise ValueError(f"invalid quantity for {sku}: {qty!r}")
        if qty < 1 or qty > LIMIT:
            raise ValueError(f"invalid quantity for {sku}: {qty!r}")
        if sku not in ordered:
            raise ValueError(f"{sku} was not ordered")
        if qty > ordered[sku]:
            raise ValueError(f"cannot return {qty} of {sku}: only {ordered[sku]} ordered")
        out.append({"sku": sku, "qty": qty})
    return out


def refund_cents(order, lines):
    """The refund in cents for returning ``lines``."""
    returned = return_items(order, lines)
    unit = {item["sku"]: item["cents"] // item["qty"] for item in order["items"]}
    return sum(unit[line["sku"]] * line["qty"] for line in returned)


def exchange(catalog, order, back_lines, new_lines):
    """Return ``back_lines`` and take ``new_lines`` instead; the result's ``due_cents`` is what the customer pays."""
    returned = return_items(order, back_lines)
    unit = {item["sku"]: item["cents"] // item["qty"] for item in order["items"]}
    taken = []
    for sku, qty in new_lines:
        if not isinstance(sku, str) or SKU_PATTERN.fullmatch(sku) is None:
            raise ValueError(f"invalid sku: {sku!r}")
        if isinstance(qty, bool) or not isinstance(qty, int) or not 1 <= qty <= LIMIT:
            raise ValueError(f"invalid quantity for {sku}: {qty!r}")
        taken.append({"sku": sku, "qty": qty, "cents": catalog.get(sku).price_cents * qty})
    credit = sum(unit[line["sku"]] * line["qty"] for line in returned)
    return {"returned": returned, "taken": taken, "due_cents": sum(t["cents"] for t in taken) - credit}
