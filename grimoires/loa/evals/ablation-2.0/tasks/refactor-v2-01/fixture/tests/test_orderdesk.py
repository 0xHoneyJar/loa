import pytest

from orderdesk import orders, quotes, report, returns, transfers
from orderdesk.catalog import Catalog, Product


@pytest.fixture
def catalog():
    return Catalog([
        Product("ABC-0001", "Widget", 250),
        Product("ABC-0002", "Gadget  large", 1000),
        Product("XYZ-9000", "Bolt", 5),
    ])


def test_place_order_merges_repeated_skus(catalog):
    order = orders.place_order(catalog, [("ABC-0002", 1), ("ABC-0001", 2), ("ABC-0001", 3)])
    assert order == {
        "items": [{"sku": "ABC-0001", "qty": 5, "cents": 1250}, {"sku": "ABC-0002", "qty": 1, "cents": 1000}],
        "total_cents": 2250,
    }


def test_place_order_needs_a_line_and_known_skus(catalog):
    with pytest.raises(ValueError, match="^an order needs at least one line$"):
        orders.place_order(catalog, [])
    with pytest.raises(KeyError, match="unknown sku: 'QQQ-0001'"):
        orders.place_order(catalog, [("QQQ-0001", 1)])


@pytest.mark.parametrize("sku", ["abc-0001", "ABC-001", "ABC0001", " ABC-0001", 7, None])
def test_orders_reject_bad_skus(catalog, sku):
    with pytest.raises(ValueError, match="^invalid sku: "):
        orders.place_order(catalog, [(sku, 1)])
    with pytest.raises(ValueError) as exc:
        orders.order_total(catalog, [(sku, 1)])
    assert str(exc.value) == f"invalid sku: {sku!r}"


@pytest.mark.parametrize("qty", [0, -1, 1000, True, 1.0, "2"])
def test_orders_reject_bad_quantities(catalog, qty):
    with pytest.raises(ValueError) as exc:
        orders.place_order(catalog, [("ABC-0001", qty)])
    assert str(exc.value) == f"invalid quantity for ABC-0001: {qty!r}"
    with pytest.raises(ValueError, match="^invalid quantity for ABC-0001: "):
        orders.order_total(catalog, [("ABC-0001", qty)])


def test_order_total_and_limit(catalog):
    assert orders.order_total(catalog, [("XYZ-9000", 999), ("ABC-0001", 1)]) == 5245


def test_a_bad_sku_is_reported_before_a_bad_quantity(catalog):
    with pytest.raises(ValueError, match="^invalid sku: 'bad'$"):
        orders.order_total(catalog, [("bad", 0)])
    with pytest.raises(ValueError, match="^invalid sku: 'BAD'$"):
        returns.return_items({"items": []}, [("bad", 0)])


def test_returns_clean_the_sku(catalog):
    order = orders.place_order(catalog, [("ABC-0001", 4)])
    assert returns.return_items(order, [(" abc-0001 ", 2)]) == [{"sku": "ABC-0001", "qty": 2}]
    assert returns.refund_cents(order, [("abc-0001", 3)]) == 750


def test_return_messages_name_the_cleaned_sku(catalog):
    order = orders.place_order(catalog, [("ABC-0001", 4)])
    with pytest.raises(ValueError) as exc:
        returns.return_items(order, [(" abc-0001", 0)])
    assert str(exc.value) == "invalid quantity for ABC-0001: 0"
    with pytest.raises(ValueError) as exc:
        returns.return_items(order, [("ab-1", 1)])
    assert str(exc.value) == "invalid sku: 'AB-1'"
    with pytest.raises(ValueError, match="^invalid quantity for ABC-0001: False$"):
        returns.return_items(order, [("ABC-0001", False)])


def test_returns_are_bounded_by_the_order(catalog):
    order = orders.place_order(catalog, [("ABC-0001", 4)])
    with pytest.raises(ValueError, match="^ABC-0002 was not ordered$"):
        returns.return_items(order, [("ABC-0002", 1)])
    with pytest.raises(ValueError, match="^cannot return 5 of ABC-0001: only 4 ordered$"):
        returns.return_items(order, [("ABC-0001", 5)])


def test_plan_transfer_moves_stock():
    stock = {"NORTH": {"ABC-0001": 10}, "SOUTH": {}}
    after = transfers.plan_transfer(stock, [("ABC-0001", 4)], "NORTH", "SOUTH")
    assert after == {"NORTH": {"ABC-0001": 6}, "SOUTH": {"ABC-0001": 4}, "EAST": {}}
    assert stock == {"NORTH": {"ABC-0001": 10}, "SOUTH": {}}


def test_plan_transfer_errors():
    stock = {"NORTH": {"ABC-0001": 10}}
    with pytest.raises(ValueError, match="^unknown warehouse: WEST$"):
        transfers.plan_transfer(stock, [], "NORTH", "WEST")
    with pytest.raises(ValueError, match="^source and destination are the same$"):
        transfers.plan_transfer(stock, [], "NORTH", "NORTH")
    with pytest.raises(ValueError, match="^ABC-0001 listed twice$"):
        transfers.plan_transfer(stock, [("ABC-0001", 1), ("ABC-0001", 1)], "NORTH", "EAST")
    with pytest.raises(ValueError, match="^only 10 of ABC-0001 in NORTH$"):
        transfers.plan_transfer(stock, [("ABC-0001", 11)], "NORTH", "EAST")
    with pytest.raises(ValueError, match="^invalid quantity for ABC-0001: 1000$"):
        transfers.plan_transfer(stock, [("ABC-0001", 1000)], "NORTH", "EAST")
    with pytest.raises(ValueError, match="^invalid sku: 'abc-0001'$"):
        transfers.plan_transfer(stock, [("abc-0001", 1)], "NORTH", "EAST")


def test_split_transfer():
    assert transfers.split_transfer([("ABC-0001", 7), ("XYZ-9000", 1)], 3) == [
        [("ABC-0001", 3), ("XYZ-9000", 1)],
        [("ABC-0001", 2)],
        [("ABC-0001", 2)],
    ]
    with pytest.raises(ValueError, match="^invalid parts: True$"):
        transfers.split_transfer([], True)
    with pytest.raises(ValueError, match="^invalid quantity for ABC-0001: 0$"):
        transfers.split_transfer([("ABC-0001", 0)], 2)
    with pytest.raises(ValueError, match="^invalid sku: None$"):
        transfers.split_transfer([(None, 1)], 2)


def test_quote_discounts(catalog):
    q = quotes.quote(catalog, [("ABC-0001", 9), ("ABC-0001", 10), ("XYZ-9000", 100)])
    assert [r["discount_pct"] for r in q["rows"]] == [0, 5, 10]
    assert q["total_cents"] == 2250 + 2375 + 450


def test_bulk_quote_allows_larger_quantities(catalog):
    q = quotes.bulk_quote(catalog, [("XYZ-9000", 9999)])
    assert q["bulk"] is True and q["rows"][0]["discount_pct"] == 15 and q["total_cents"] == 42495
    with pytest.raises(ValueError, match="^invalid quantity for XYZ-9000: 1000$"):
        quotes.quote(catalog, [("XYZ-9000", 1000)])
    with pytest.raises(ValueError, match="^invalid quantity for XYZ-9000: 10000$"):
        quotes.bulk_quote(catalog, [("XYZ-9000", 10000)])
    with pytest.raises(ValueError, match="^invalid sku: 'xyz-9000'$"):
        quotes.bulk_quote(catalog, [("xyz-9000", 1)])
    with pytest.raises(ValueError, match="^invalid quantity for XYZ-9000: True$"):
        quotes.bulk_quote(catalog, [("XYZ-9000", True)])


def test_report_lines(catalog):
    order = orders.place_order(catalog, [("ABC-0002", 2)])
    assert report.order_lines(catalog, order) == [
        "ABC-0002  Gadget large         x   2       20.00",
        "TOTAL                                 20.00",
    ]
    q = quotes.quote(catalog, [("ABC-0001", 10)])
    assert report.quote_lines(catalog, q) == ["ABC-0001  Widget x10 -5%  23.75", "TOTAL 23.75"]
    assert report.format_cents(-5) == "-0.05"


def test_exchange_cleans_returned_skus_but_not_new_ones(catalog):
    order = orders.place_order(catalog, [("ABC-0001", 4)])
    result = returns.exchange(catalog, order, [("abc-0001", 2)], [("XYZ-9000", 3)])
    assert result == {
        "returned": [{"sku": "ABC-0001", "qty": 2}],
        "taken": [{"sku": "XYZ-9000", "qty": 3, "cents": 15}],
        "due_cents": -485,
    }
    with pytest.raises(ValueError, match="^invalid sku: 'xyz-9000'$"):
        returns.exchange(catalog, order, [("ABC-0001", 1)], [("xyz-9000", 1)])
    with pytest.raises(ValueError, match="^invalid quantity for XYZ-9000: 1000$"):
        returns.exchange(catalog, order, [], [("XYZ-9000", 1000)])
