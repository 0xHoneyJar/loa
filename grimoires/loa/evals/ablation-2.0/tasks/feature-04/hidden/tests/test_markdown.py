import pytest

from tabular import Column, render

ROWS = [{"name": "alpha", "qty": 3, "price": 1.5}, {"name": "beta", "qty": 12, "price": None}]


def md(rows, cols):
    return render(rows, cols, fmt="markdown")


def test_left_aligned_table():
    assert md(ROWS, [Column("name"), Column("qty")]) == (
        "| name  | qty |\n"
        "| :---- | :-- |\n"
        "| alpha | 3   |\n"
        "| beta  | 12  |\n"
    )


def test_right_and_center_alignment():
    cols = [Column("name", align="center"), Column("price", align="right")]
    assert md(ROWS, cols) == (
        "| name  | price |\n"
        "| :---: | ----: |\n"
        "| alpha |  1.50 |\n"
        "| beta  |       |\n"
    )


def test_center_puts_the_odd_space_on_the_right():
    cols = [Column("Label", key="name", align="center")]
    assert md([{"name": "ab"}, {"name": "abcdefg"}], cols) == (
        "|  Label  |\n"
        "| :-----: |\n"
        "|   ab    |\n"
        "| abcdefg |\n"
    )


def test_minimum_width_is_three():
    cols = [Column("a"), Column("b", align="right"), Column("c", align="center")]
    assert md([{"a": 1, "b": 2, "c": 3}], cols) == (
        "| a   |   b |  c  |\n"
        "| :-- | --: | :-: |\n"
        "| 1   |   2 |  3  |\n"
    )


def test_pipes_are_escaped_and_counted_in_the_width():
    cols = [Column("a|b", key="v")]
    assert md([{"v": "x|y|z"}], cols) == (
        "| a\\|b    |\n"
        "| :------ |\n"
        "| x\\|y\\|z |\n"
    )


def test_line_breaks_become_one_space():
    assert md([{"v": "one\ntwo\r\nthree\rfour"}], [Column("v")]) == (
        "| v                  |\n"
        "| :----------------- |\n"
        "| one two three four |\n"
    )


def test_cells_use_the_shared_formatting_and_missing_keys_are_empty():
    cols = [Column("ok"), Column("ratio", align="right"), Column("gone")]
    assert md([{"ok": True, "ratio": 0.5}, {"ok": False, "ratio": 2.0, "gone": None}], cols) == (
        "| ok    | ratio | gone |\n"
        "| :---- | ----: | :--- |\n"
        "| true  |  0.50 |      |\n"
        "| false |  2.00 |      |\n"
    )


def test_no_rows_gives_header_and_separator_only():
    assert md([], [Column("name"), Column("qty", align="right")]) == "| name | qty |\n| :--- | --: |\n"


def test_errors_and_text_format_unchanged():
    with pytest.raises(ValueError):
        md(ROWS, [])
    with pytest.raises(ValueError):
        render(ROWS, [Column("name")], fmt="html")
    assert render(ROWS, [Column("name")]) == "name\n-----\nalpha\nbeta\n"
    assert md(iter(ROWS), [Column("qty")]) == "| qty |\n| :-- |\n| 3   |\n| 12  |\n"
