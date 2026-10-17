"""Stock transfers between the warehouses."""
import re

WAREHOUSES = ("NORTH", "SOUTH", "EAST")


def plan_transfer(stock, lines, src, dst):
    """Stock after moving ``lines`` from ``src`` to ``dst``; ``stock`` maps warehouse -> {sku: qty}."""
    for name in (src, dst):
        if name not in WAREHOUSES:
            raise ValueError(f"unknown warehouse: {name}")
    if src == dst:
        raise ValueError("source and destination are the same")
    moves = []
    seen = set()
    for sku, qty in lines:
        if not isinstance(sku, str) or re.fullmatch(r"[A-Z]{3}-[0-9]{4}", sku) is None:
            raise ValueError(f"invalid sku: {sku!r}")
        if isinstance(qty, bool) or not isinstance(qty, int) or not 0 < qty <= 999:
            raise ValueError(f"invalid quantity for {sku}: {qty!r}")
        if sku in seen:
            raise ValueError(f"{sku} listed twice")
        seen.add(sku)
        have = stock.get(src, {}).get(sku, 0)
        if qty > have:
            raise ValueError(f"only {have} of {sku} in {src}")
        moves.append((sku, qty))
    after = {name: dict(stock.get(name, {})) for name in WAREHOUSES}
    for sku, qty in moves:
        after[src][sku] -= qty
        after[dst][sku] = after[dst].get(sku, 0) + qty
    return after


def split_transfer(lines, parts):
    """Split ``lines`` into ``parts`` shipments as evenly as possible; earlier parts get the remainder."""
    if type(parts) is not int or parts < 1:
        raise ValueError(f"invalid parts: {parts!r}")
    shipments = [[] for _ in range(parts)]
    for sku, qty in lines:
        if not isinstance(sku, str) or not re.fullmatch(r"[A-Z]{3}-[0-9]{4}", sku):
            raise ValueError(f"invalid sku: {sku!r}")
        if isinstance(qty, bool) or not isinstance(qty, int) or qty < 1 or qty > 999:
            raise ValueError(f"invalid quantity for {sku}: {qty!r}")
        each, extra = divmod(qty, parts)
        for i in range(parts):
            n = each + (1 if i < extra else 0)
            if n:
                shipments[i].append((sku, n))
    return shipments
