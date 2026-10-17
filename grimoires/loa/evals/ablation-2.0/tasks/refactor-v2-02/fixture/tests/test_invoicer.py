import io

import pytest

from invoicer import api, batch, cli
from invoicer.pricing import Discount, Item, ParseError, PricingError, invoice_totals, parse_invoice

INVOICE = """# a sample
customer: ACME Ltd
currency: EUR
item: Widget | 3 | 12.50 | std
item: Book | 1 | 9.99 | reduced
discount: 10%
"""

RENDERED = """INVOICE for ACME Ltd (EUR)
  3 x Widget                     EUR 37.50  std
  1 x Book                        EUR 9.99  reduced
Subtotal                         EUR 47.49
Discount 10%                     EUR -4.75
Tax reduced 5%                    EUR 0.45
Tax std 20%                       EUR 6.75
Total                            EUR 49.94
"""


def test_parse_invoice():
    inv = parse_invoice(INVOICE)
    assert inv.customer == "ACME Ltd" and inv.currency == "EUR"
    assert inv.items == (Item("Widget", 3, 1250, "std"), Item("Book", 1, 999, "reduced"))
    assert inv.discount == Discount("pct", 10)


@pytest.mark.parametrize("text,message", [
    ("customer: A\ncurrency: EUR\nitem: x | 1 | 1.00\n", "line 3: an item has 4 fields, got 3"),
    ("customer: A\ncurrency: EUR\nitem: x | 0 | 1.00 | std\n", "line 3: bad quantity '0'"),
    ("customer: A\ncurrency: EUR\nitem: x | 1 | 1.005 | std\n", "line 3: not an amount: '1.005'"),
    ("customer: A\ncurrency: EUR\nitem: x | 1 | 1.00 | luxury\n", "line 3: unknown tax class 'luxury'"),
    ("customer: A\ncurrency: XYZ\n", "line 2: bad or repeated currency 'XYZ'"),
    ("customer: A\nnote: hi\n", "line 2: unknown key 'note'"),
    ("customer A\n", "line 1: expected 'key: value'"),
    ("customer: A\ncurrency: EUR\nitem: x | 1 | 1.00 | std\ndiscount: 0%\n", "line 4: bad discount '0%'"),
    ("customer: A\ncurrency: EUR\nitem: x | 1 | 1.00 | std\ndiscount: 5\ndiscount: 5\n", "line 5: discount given twice"),
    ("currency: EUR\n", "missing customer"),
    ("customer: A\ncurrency: EUR\n", "missing items"),
])
def test_parse_errors(text, message):
    with pytest.raises(ParseError) as exc:
        parse_invoice(text)
    assert str(exc.value) == message


def test_totals_with_a_percent_discount():
    t = invoice_totals(parse_invoice(INVOICE))
    assert (t.subtotal, t.discount, t.tax, t.total) == (4749, 475, 720, 4994)
    assert t.tax_by_class == (("reduced", 45), ("std", 675))


def test_absolute_discount_spreads_with_the_remainder_on_the_largest_line():
    text = "customer: B\ncurrency: GBP\nitem: a | 1 | 1.00 | std\nitem: b | 1 | 1.00 | zero\nitem: c | 1 | 1.00 | std\ndiscount: 0.01\n"
    t = invoice_totals(parse_invoice(text))
    assert (t.subtotal, t.discount, t.total) == (300, 1, 299 + 40)
    assert t.tax_by_class == (("std", 40), ("zero", 0))


def test_discount_above_the_subtotal_is_a_pricing_error():
    text = "customer: B\ncurrency: GBP\nitem: a | 2 | 1.00 | std\ndiscount: 50\n"
    with pytest.raises(PricingError) as exc:
        invoice_totals(parse_invoice(text))
    assert str(exc.value) == "discount GBP 50.00 exceeds subtotal GBP 2.00"


def test_process_renders_the_invoice():
    assert api.process(INVOICE) == RENDERED
    assert api.total_of(INVOICE) == 4994


def test_render_absolute_discount_label():
    text = "customer: C\ncurrency: USD\nitem: pen | 2 | 0.50 | zero\ndiscount: 0.25\n"
    assert api.process(text).splitlines()[2:] == [
        "Subtotal                          USD 1.00",
        "Discount                         USD -0.25",
        "Tax zero 0%                       USD 0.00",
        "Total                             USD 0.75",
    ]


def test_batch_summary_reports_errors_and_sums_per_currency():
    usd = "customer: C\ncurrency: USD\nitem: pen | 2 | 0.50 | zero\n"
    out = batch.summary([INVOICE, "customer: D\n", usd, usd])
    assert out == (
        "ACME Ltd: EUR 49.94\nC: USD 1.00\nC: USD 1.00\ninvoices: 3\n"
        "total EUR 49.94; USD 2.00\nerror in invoice 2: missing currency\n"
    )
    assert batch.summary([]) == "invoices: 0\n"


def run_cli(argv):
    out, err = io.StringIO(), io.StringIO()
    return cli.main(argv, stdout=out, stderr=err), out.getvalue(), err.getvalue()


def test_cli_render_and_total(tmp_path):
    path = tmp_path / "a.inv"
    path.write_text(INVOICE)
    assert run_cli(["render", str(path)]) == (0, RENDERED, "")
    assert run_cli(["total", str(path)]) == (0, "EUR 49.94\n", "")


def test_cli_errors(tmp_path):
    bad = tmp_path / "bad.inv"
    bad.write_text("customer: B\ncurrency: GBP\nitem: a | 2 | 1.00 | std\ndiscount: 50\n")
    assert run_cli(["total", str(bad)]) == (1, "", f"invoicer: {bad}: discount GBP 50.00 exceeds subtotal GBP 2.00\n")
    code, out, err = run_cli(["render"])
    assert code == 2 and out == "" and err.startswith("usage: invoicer render FILE")
    assert run_cli(["total", str(tmp_path / "nope")]) == (1, "", f"invoicer: {tmp_path / 'nope'}: cannot read\n")


def test_cli_batch(tmp_path):
    path = tmp_path / "a.inv"
    path.write_text(INVOICE)
    assert run_cli(["batch", str(path), str(path)]) == (
        0, "ACME Ltd: EUR 49.94\nACME Ltd: EUR 49.94\ninvoices: 2\ntotal EUR 99.88\n", "")
