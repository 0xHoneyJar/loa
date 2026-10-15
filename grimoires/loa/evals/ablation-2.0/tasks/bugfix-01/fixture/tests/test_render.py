from pagekit import nav_window, pager_bar, summary


def test_summary_last_full_page():
    assert summary(40, 10, 4) == "Showing 31-40 of 40"


def test_summary_empty():
    assert summary(0, 10, 1) == "No items"


def test_nav_at_the_end():
    assert nav_window(100, 10, 10) == [1, None, 6, 7, 8, 9, 10]


def test_pager_bar_at_the_end():
    assert pager_bar(100, 10, 10) == "1 ... 6 7 8 9 [10]"
