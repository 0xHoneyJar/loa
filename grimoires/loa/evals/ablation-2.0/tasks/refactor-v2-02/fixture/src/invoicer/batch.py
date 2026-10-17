"""Price many invoices at once; a bad invoice is reported, not fatal."""
from . import pricing


def run_batch(texts):
    """``(rows, errors)``: rows of (customer, currency, total) and errors of (index, message)."""
    rows, errors = [], []
    for index, text in enumerate(texts):
        try:
            invoice = pricing.parse_invoice(text)
            rows.append((invoice.customer, invoice.currency, pricing.invoice_totals(invoice).total))
        except (pricing.ParseError, pricing.PricingError) as exc:
            errors.append((index, str(exc)))
    return rows, errors


def summary(texts):
    rows, errors = run_batch(texts)
    text = pricing.render_summary(rows)
    return text + "".join(f"error in invoice {index + 1}: {message}\n" for index, message in errors)
