from datakit.dedupe import dedupe


def test_no_duplicates_unchanged():
    rows = [{"id": 1}, {"id": 2}, {"id": 3}]
    assert dedupe(rows, key=lambda r: r["id"]) == rows


def test_order_of_first_seen_keys():
    rows = [{"id": 2, "v": "x"}, {"id": 1, "v": "y"}, {"id": 2, "v": "z"}]
    assert [r["id"] for r in dedupe(rows, key=lambda r: r["id"])] == [2, 1]
