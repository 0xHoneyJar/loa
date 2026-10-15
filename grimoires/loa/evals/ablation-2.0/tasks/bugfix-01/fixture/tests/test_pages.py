import pytest

from pagekit import PageError, page_bounds, page_count, page_of


def test_exact_multiple():
    assert page_count(40, 10) == 4


def test_empty_listing_has_one_page():
    assert page_count(0, 10) == 1
    assert page_bounds(0, 10, 1) == (0, 0)


def test_bounds_of_a_middle_page():
    assert page_bounds(40, 10, 2) == (10, 20)


def test_page_of():
    assert page_of(40, 10, 0) == 1
    assert page_of(40, 10, 39) == 4


@pytest.mark.parametrize("args", [(40, 10, 0), (40, 10, 5), (40, 0, 1), (-1, 10, 1)])
def test_bad_input_raises(args):
    with pytest.raises(PageError):
        page_bounds(*args)
