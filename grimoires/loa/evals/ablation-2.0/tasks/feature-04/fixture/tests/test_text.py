import pytest

from tabular import Column, format_cell, render

ROWS = [{"name": "alpha", "qty": 3, "price": 1.5}, {"name": "beta", "qty": 12, "price": None}]


def test_text_table():
    cols = [Column("name"), Column("qty", align="right"), Column("price", align="right")]
    assert render(ROWS, cols) == (
        "name   qty  price\n"
        "-----  ---  -----\n"
        "alpha    3   1.50\n"
        "beta    12\n"
    )


def test_center_and_key():
    cols = [Column("Item", key="name", align="center")]
    assert render(ROWS, cols) == " Item\n-----\nalpha\n beta\n"


def test_missing_key_is_empty():
    assert render([{}], [Column("a"), Column("b")]) == "a  b\n-  -\n\n"


def test_format_cell():
    assert [format_cell(v) for v in (None, True, False, 2.0, 7, "x")] == ["", "true", "false", "2.00", "7", "x"]


def test_errors():
    with pytest.raises(ValueError):
        render(ROWS, [])
    with pytest.raises(ValueError):
        render(ROWS, [Column("name")], fmt="html")
    with pytest.raises(ValueError):
        Column("name", align="middle")
