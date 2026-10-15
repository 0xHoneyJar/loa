import pytest

from salesreport import ReportError, build_report

DATA = """date,region,product,qty,unit_price
# week 41
2026-10-06,North,Widget,10,2.50
2026-10-07,South,Gadget,3,19.99
2026-10-07,North,Gadget,1,19.99

2026-10-09,East,Widget,4,2.50
2026-10-10,South,Widget,-2,2.50
2026-10-10,East,Doohickey,1,99.00
"""

EXPECTED = """Sales summary
=============
Period:   2026-10-06 to 2026-10-10
Rows:     6
Units:    19
Revenue:  208.96 EUR
Refunds:  5.00 EUR

By region
  East         109.00   52.2%
  South         54.97   26.3%
  North         44.99   21.5%

Top 3 product(s)
  1. Doohickey (99.00 EUR)
  2. Gadget (79.96 EUR)
  3. Widget (30.00 EUR)
"""


def test_full_report():
    assert build_report(DATA) == EXPECTED


def test_currency_and_top():
    out = build_report(DATA, currency="USD", top=1)
    assert "Revenue:  208.96 USD" in out
    assert out.endswith("Top 1 product(s)\n  1. Doohickey (99.00 USD)\n")


def test_no_refund_line_without_refunds():
    out = build_report("2026-10-06,North,Widget,10,2.50\n")
    assert "Refunds" not in out
    assert "  North  " in out


def test_empty():
    assert build_report("# nothing\n\n") == "Sales summary\n=============\nNo sales.\n"


def test_thousands_separator():
    out = build_report("2026-10-06,West,Server,3,4999.99\n")
    assert "Revenue:  14,999.97 EUR" in out
    assert "  West     14,999.97  100.0%" in out


@pytest.mark.parametrize("line,msg", [
    ("2026-10-06,North,Widget,10", "line 1: expected 5 fields, got 4"),
    ("2026-13-06,North,Widget,10,2.5", "line 1: bad date '2026-13-06'"),
    ("2026-10-06,,Widget,10,2.5", "line 1: region and product are required"),
    ("2026-10-06,North,Widget,ten,2.5", "line 1: bad number"),
    ("2026-10-06,North,Widget,1,-2.5", "line 1: negative price"),
])
def test_bad_lines(line, msg):
    with pytest.raises(ReportError) as ei:
        build_report(line + "\n")
    assert str(ei.value) == msg


def test_bad_top():
    with pytest.raises(ReportError):
        build_report(DATA, top=0)
