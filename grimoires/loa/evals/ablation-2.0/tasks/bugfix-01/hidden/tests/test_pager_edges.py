import pytest

from pagekit import PageError, nav_window, page_bounds, page_count, page_of, pager_bar, summary


@pytest.mark.parametrize("total,per_page,want", [(45, 10, 5), (41, 10, 5), (40, 10, 4), (1, 10, 1), (0, 10, 1), (7, 1, 7), (3, 7, 1)])
def test_page_count_rounds_up(total, per_page, want):
    assert page_count(total, per_page) == want


def test_partial_last_page():
    assert page_bounds(45, 10, 5) == (40, 45)
    assert summary(45, 10, 5) == "Showing 41-45 of 45"
    with pytest.raises(PageError):
        page_bounds(45, 10, 6)


def test_every_item_lives_on_an_existing_page():
    for total in (1, 9, 10, 11, 45, 99):
        for per_page in (1, 3, 10):
            pages = page_count(total, per_page)
            for index in range(total):
                page = page_of(total, per_page, index)
                assert 1 <= page <= pages
                start, end = page_bounds(total, per_page, page)
                assert start <= index < end


def test_nav_run_has_full_width_at_the_start_and_middle():
    assert nav_window(100, 10, 1) == [1, 2, 3, 4, 5, None, 10]
    assert nav_window(100, 10, 5) == [1, None, 3, 4, 5, 6, 7, None, 10]
    assert pager_bar(100, 10, 5) == "1 ... 3 4 [5] 6 7 ... 10"


def test_nav_at_the_end_is_unchanged():
    assert nav_window(100, 10, 10) == [1, None, 6, 7, 8, 9, 10]
    assert nav_window(45, 10, 5) == [1, 2, 3, 4, 5]


def test_nav_of_a_single_page_listing():
    assert nav_window(0, 10, 1) == [1]
    assert nav_window(3, 10, 1) == [1]
    assert pager_bar(0, 10, 1) == "[1]"


def test_nav_shorter_than_width():
    assert nav_window(30, 10, 2) == [1, 2, 3]
    assert nav_window(60, 10, 4, width=3) == [1, None, 3, 4, 5, 6]
