"""Build the weekly sales summary.

Input lines are ``date,region,product,qty,unit_price``. Blank lines, lines
starting with ``#`` and a header line starting with ``date,`` are skipped. A
negative ``qty`` is a refund.
"""
import datetime


class ReportError(ValueError):
    """A malformed input line."""


def build_report(text: str, *, currency: str = "EUR", top: int = 3) -> str:
    """The summary as text: totals, revenue per region, the top products."""
    if top < 1:
        raise ReportError("top must be at least 1")
    sales = []
    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.lower().startswith("date,"):
            continue
        parts = [p.strip() for p in line.split(",")]
        if len(parts) != 5:
            raise ReportError(f"line {lineno}: expected 5 fields, got {len(parts)}")
        day_s, region, product, qty_s, price_s = parts
        try:
            day = datetime.date.fromisoformat(day_s)
        except ValueError:
            raise ReportError(f"line {lineno}: bad date {day_s!r}") from None
        if not region or not product:
            raise ReportError(f"line {lineno}: region and product are required")
        try:
            qty = int(qty_s)
            price = round(float(price_s), 2)
        except ValueError:
            raise ReportError(f"line {lineno}: bad number") from None
        if price < 0:
            raise ReportError(f"line {lineno}: negative price")
        sales.append((day, region, product, qty, price))
    revenue = 0.0
    refunds = 0.0
    units = 0
    by_region = {}
    by_product = {}
    first = last = None
    for day, region, product, qty, price in sales:
        amount = round(qty * price, 2)
        if qty < 0:
            refunds += -amount
        else:
            units += qty
        revenue += amount
        by_region[region] = by_region.get(region, 0.0) + amount
        by_product[product] = by_product.get(product, 0.0) + amount
        if first is None or day < first:
            first = day
        if last is None or day > last:
            last = day
    regions = sorted(by_region.items(), key=lambda kv: (-kv[1], kv[0]))
    products = sorted(by_product.items(), key=lambda kv: (-kv[1], kv[0]))[:top]
    lines = []
    lines.append("Sales summary")
    lines.append("=============")
    if not sales:
        lines.append("No sales.")
        return "\n".join(lines) + "\n"
    lines.append(f"Period:   {first.isoformat()} to {last.isoformat()}")
    lines.append(f"Rows:     {len(sales)}")
    lines.append(f"Units:    {units}")
    lines.append(f"Revenue:  {revenue:,.2f} {currency}")
    if refunds:
        lines.append(f"Refunds:  {refunds:,.2f} {currency}")
    lines.append("")
    lines.append("By region")
    width = max(len(r) for r, _ in regions)
    for region, amount in regions:
        share = 0.0 if revenue == 0 else 100.0 * amount / revenue
        lines.append(f"  {region.ljust(width)}  {amount:>12,.2f}  {share:5.1f}%")
    lines.append("")
    lines.append(f"Top {len(products)} product(s)")
    for rank, (product, amount) in enumerate(products, start=1):
        lines.append(f"  {rank}. {product} ({amount:,.2f} {currency})")
    return "\n".join(lines) + "\n"
