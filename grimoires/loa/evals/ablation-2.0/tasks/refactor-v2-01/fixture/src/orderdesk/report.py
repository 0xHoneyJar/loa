"""Plain-text summaries of orders and quotes."""
import re


def format_cents(cents):
    sign = "-" if cents < 0 else ""
    cents = abs(cents)
    return f"{sign}{cents // 100}.{cents % 100:02d}"


def _clean(name):
    return re.sub(r"\s+", " ", name).strip()


def order_lines(catalog, order):
    """One line per item and a total line."""
    lines = [
        f"{item['sku']}  {_clean(catalog.get(item['sku']).name):<20} x{item['qty']:>4}  {format_cents(item['cents']):>10}"
        for item in order["items"]
    ]
    lines.append(f"{'TOTAL':<31}  {format_cents(order['total_cents']):>10}")
    return lines


def quote_lines(catalog, quote):
    """One line per quoted row (with its discount) and a total line."""
    lines = []
    for row in quote["rows"]:
        off = f" -{row['discount_pct']}%" if row["discount_pct"] else ""
        lines.append(f"{row['sku']}  {_clean(catalog.get(row['sku']).name)} x{row['qty']}{off}  {format_cents(row['cents'])}")
    lines.append(f"TOTAL {format_cents(quote['total_cents'])}")
    return lines
