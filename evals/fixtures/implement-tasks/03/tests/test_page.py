import pytest
from listkit.page import paginate


def test_page_size():
    assert len(paginate(list(range(10)), 1, 3)) == 3


def test_empty():
    assert paginate([], 1, 3) == []


def test_invalid():
    with pytest.raises(ValueError):
        paginate([1], 0, 3)
    with pytest.raises(ValueError):
        paginate([1], 1, 0)
