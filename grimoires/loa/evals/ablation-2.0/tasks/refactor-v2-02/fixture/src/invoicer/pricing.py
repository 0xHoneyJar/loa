"""Invoice pricing: line totals, the discount and tax.

This module also parses the invoice text format and renders a priced invoice
as text, because that is where the code first grew.
"""
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation

TAX_RATES = {"std": 20, "reduced": 5, "zero": 0}
CURRENCIES = ("EUR", "GBP", "USD")


class ParseError(ValueError):
    """A malformed invoice."""


class PricingError(ValueError):
    """An invoice that parses but cannot be priced."""


@dataclass(frozen=True)
class Item:
    name: str
    qty: int
    unit_cents: int
    tax_class: str


@dataclass(frozen=True)
class Discount:
    kind: str
    value: int


@dataclass(frozen=True)
class Invoice:
    customer: str
    currency: str
    items: tuple
    discount: object = None


@dataclass(frozen=True)
class Totals:
    subtotal: int
    discount: int
    tax: int
    total: int
    tax_by_class: tuple


def parse_amount(text):
    """``"12.50"`` -> 1250; not negative, at most two decimals."""
    try:
        value = Decimal(text)
    except InvalidOperation:
        raise ValueError(f"not an amount: {text!r}") from None
    if not value.is_finite() or value < 0 or value.as_tuple().exponent < -2:
        raise ValueError(f"not an amount: {text!r}")
    return int(value * 100)


def format_money(cents, currency):
    sign = "-" if cents < 0 else ""
    return f"{currency} {sign}{abs(cents) // 100}.{abs(cents) % 100:02d}"


def parse_invoice(text):
    """Parse the ``key: value`` invoice format into an ``Invoice``."""
    customer = currency = discount = None
    items = []
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition(":")
        key, value = key.strip().lower(), value.strip()
        if not sep:
            raise ParseError(f"line {number}: expected 'key: value'")
        if key == "customer":
            if customer is not None or not value:
                raise ParseError(f"line {number}: bad or repeated customer")
            customer = value
        elif key == "currency":
            if currency is not None or value not in CURRENCIES:
                raise ParseError(f"line {number}: bad or repeated currency {value!r}")
            currency = value
        elif key == "item":
            parts = [part.strip() for part in value.split("|")]
            if len(parts) != 4:
                raise ParseError(f"line {number}: an item has 4 fields, got {len(parts)}")
            name, qty_text, price_text, tax_class = parts
            if not name:
                raise ParseError(f"line {number}: empty item name")
            if not qty_text.isdigit() or int(qty_text) < 1:
                raise ParseError(f"line {number}: bad quantity {qty_text!r}")
            if tax_class not in TAX_RATES:
                raise ParseError(f"line {number}: unknown tax class {tax_class!r}")
            try:
                items.append(Item(name, int(qty_text), parse_amount(price_text), tax_class))
            except ValueError as exc:
                raise ParseError(f"line {number}: {exc}") from None
        elif key == "discount":
            if discount is not None:
                raise ParseError(f"line {number}: discount given twice")
            pct = value[:-1].strip() if value.endswith("%") else None
            if pct is not None and (not pct.isdigit() or not 0 < int(pct) <= 100):
                raise ParseError(f"line {number}: bad discount {value!r}")
            try:
                discount = Discount("pct", int(pct)) if pct is not None else Discount("abs", parse_amount(value))
            except ValueError as exc:
                raise ParseError(f"line {number}: {exc}") from None
        else:
            raise ParseError(f"line {number}: unknown key {key!r}")
    for label, present in (("customer", customer), ("currency", currency), ("items", items)):
        if not present:
            raise ParseError(f"missing {label}")
    return Invoice(customer, currency, tuple(items), discount)


def line_total(item):
    return item.qty * item.unit_cents


def invoice_totals(invoice):
    """Price ``invoice``; the discount is spread over the lines in proportion to their net."""
    nets = [line_total(item) for item in invoice.items]
    subtotal = sum(nets)
    discount = invoice.discount
    if discount is None:
        off = 0
    elif discount.kind == "pct":
        off = (subtotal * discount.value + 50) // 100
    elif discount.value > subtotal:
        raise PricingError(
            f"discount {format_money(discount.value, invoice.currency)} exceeds subtotal {format_money(subtotal, invoice.currency)}"
        )
    else:
        off = discount.value
    shares = [off * net // subtotal if subtotal else 0 for net in nets]
    rest = off - sum(shares)
    if rest:
        biggest = max(range(len(nets)), key=lambda i: (nets[i], -i))
        shares[biggest] += rest
    tax_by_class = {}
    for item, net, share in zip(invoice.items, nets, shares):
        tax = ((net - share) * TAX_RATES[item.tax_class] + 50) // 100
        tax_by_class[item.tax_class] = tax_by_class.get(item.tax_class, 0) + tax
    tax = sum(tax_by_class.values())
    return Totals(subtotal, off, tax, subtotal - off + tax, tuple(sorted(tax_by_class.items())))


def render_invoice(invoice, totals):
    """The invoice as text: a header, one line per item, then the totals."""
    cur = invoice.currency
    out = [f"INVOICE for {invoice.customer} ({cur})"]
    for item in invoice.items:
        label = f"{item.qty:>3} x {item.name}"
        out.append(f"{label:<28}{format_money(line_total(item), cur):>14}  {item.tax_class}")
    out.append(f"{'Subtotal':<28}{format_money(totals.subtotal, cur):>14}")
    if invoice.discount is not None:
        label = f"Discount {invoice.discount.value}%" if invoice.discount.kind == "pct" else "Discount"
        out.append(f"{label:<28}{format_money(-totals.discount, cur):>14}")
    for tax_class, cents in totals.tax_by_class:
        label = f"Tax {tax_class} {TAX_RATES[tax_class]}%"
        out.append(f"{label:<28}{format_money(cents, cur):>14}")
    out.append(f"{'Total':<28}{format_money(totals.total, cur):>14}")
    return "\n".join(out) + "\n"


def render_summary(rows):
    """``rows`` of (customer, currency, total cents) -> one line each, then the totals per currency."""
    out = [f"{customer}: {format_money(total, currency)}" for customer, currency, total in rows]
    sums = {}
    for _, currency, total in rows:
        sums[currency] = sums.get(currency, 0) + total
    out.append(f"invoices: {len(rows)}")
    if sums:
        out.append("total " + "; ".join(format_money(sums[c], c) for c in sorted(sums)))
    return "\n".join(out) + "\n"
