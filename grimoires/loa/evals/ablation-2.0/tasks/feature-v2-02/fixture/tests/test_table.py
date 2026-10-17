import io

from tally.cli import main

DATA = "name,team,score\nada,red,7\nbo,blue,12\ncy,red,\ndee,blue,7\n"


def run(argv, text=DATA):
    out, err = io.StringIO(), io.StringIO()
    code = main(argv, stdin=io.StringIO(text), stdout=out, stderr=err)
    return code, out.getvalue(), err.getvalue()


def test_plain_table_aligns_numbers_right():
    assert run([]) == (0, "name  team  score\nada   red       7\nbo    blue     12\ncy    red\ndee   blue      7\n4 rows\n", "")


def test_markdown_table():
    code, out, _ = run(["--format", "markdown"])
    assert out.splitlines() == [
        "| name | team | score |",
        "| ---- | ---- | ----: |",
        "| ada  | red  |     7 |",
        "| bo   | blue |    12 |",
        "| cy   | red  |       |",
        "| dee  | blue |     7 |",
        "4 rows",
    ]


def test_markdown_minimum_width():
    code, out, _ = run(["--format", "markdown"], "a,b\nx,1\n")
    assert out == "| a   |   b |\n| --- | --: |\n| x   |   1 |\n1 row\n"


def test_where_filters_and_footer_counts_kept_rows():
    code, out, _ = run(["--where", "team=red", "--where", "score=7"])
    assert out == "name  team  score\nada   red       7\n1 row\n"


def test_where_on_unknown_field():
    assert run(["--where", "colour=red"]) == (2, "", "tally: unknown field: colour\n")


def test_bad_where_value():
    assert run(["--where", "team"]) == (2, "", "tally: invalid --where value: team\n")


def test_empty_result_keeps_the_header():
    assert run(["--where", "team=green"])[1] == "name  team  score\n0 rows\n"


def test_unknown_format_and_option():
    assert run(["--format", "html"])[2] == "tally: unknown format: html\n"
    assert run(["--limitless"])[2] == "tally: unknown option: --limitless\n"


def test_reader_errors():
    assert run([], "")[2] == "tally: input has no header\n"
    assert run([], "a,b\n1\n")[2] == "tally: line 2 has 1 fields, expected 2\n"
