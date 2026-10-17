from test_table import run


def test_numeric_sort_ascending_keeps_ties_and_puts_empty_last():
    code, out, _ = run(["--sort", "score"])
    assert [line.split()[0] for line in out.splitlines()[1:-1]] == ["ada", "dee", "bo", "cy"]


def test_numeric_sort_descending_keeps_ties_in_input_order():
    code, out, _ = run(["--sort", "-score"])
    assert [line.split()[0] for line in out.splitlines()[1:-1]] == ["bo", "ada", "dee", "cy"]


def test_string_sort():
    code, out, _ = run(["--sort", "-team"])
    assert [line.split()[0] for line in out.splitlines()[1:-1]] == ["ada", "cy", "bo", "dee"]


def test_numeric_compare_by_value_not_text():
    code, out, _ = run(["--sort", "n"], "n\n10\n9\n-1\n2.5\n")
    assert out.splitlines()[1:-1] == [" -1", "2.5", "  9", " 10"]


def test_sort_unknown_field():
    assert run(["--sort", "age"])[2] == "tally: unknown field: age\n"
