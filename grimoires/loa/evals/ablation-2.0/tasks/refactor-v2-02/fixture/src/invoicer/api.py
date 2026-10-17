"""The two calls most callers need."""
from .pricing import invoice_totals, parse_invoice, render_invoice


def process(text):
    """The rendered invoice for the invoice ``text``."""
    invoice = parse_invoice(text)
    return render_invoice(invoice, invoice_totals(invoice))


def total_of(text):
    """The total in cents of the invoice ``text``."""
    return invoice_totals(parse_invoice(text)).total
