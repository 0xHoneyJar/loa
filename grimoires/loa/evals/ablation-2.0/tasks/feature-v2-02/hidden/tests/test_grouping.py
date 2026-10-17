import io

from tally.cli import main

SALES = (
    "region,product,units,price\n"
    "north,apple,3,1.50\n"
    "south,pear,,2\n"
    "north,pear,5,2.25\n"
    "east,apple,2,1.5\n"
    "south,apple,4,\n"
    "north,apple,1,0.75\n"
)


def run(argv, text=SALES):
    out, err = io.StringIO(), io.StringIO()
    code = main(argv, stdin=io.StringIO(text), stdout=out, stderr=err)
    return code, out.getvalue(), err.getvalue()


def lines(argv, text=SALES):
    code, out, err = run(argv, text)
    assert (code, err) == (0, "")
    return out.splitlines()


def usage_error(argv, message, text=SALES):
    assert run(argv, text) == (2, "", f"tally: {message}\n")


def keys(output, n=1):
    return [tuple(line.split()[:n]) for line in output[1:-1]]


def test_default_aggregate_is_count_in_first_appearance_order():
    assert lines(["--group-by", "region"]) == [
        "region  count",
        "north       3",
        "south       2",
        "east        1",
        "3 groups from 6 rows",
    ]


def test_two_keys_and_several_aggregates_in_markdown():
    argv = ["--group-by", "region,product", "--agg", "count", "--agg", "sum:units", "--agg", "max:price", "--format", "markdown"]
    assert lines(argv) == [
        "| region | product | count | sum(units) | max(price) |",
        "| ------ | ------- | ----: | ---------: | ---------: |",
        "| north  | apple   |     2 |          4 |       1.50 |",
        "| south  | pear    |     1 |            |          2 |",
        "| north  | pear    |     1 |          5 |       2.25 |",
        "| east   | apple   |     1 |          2 |        1.5 |",
        "| south  | apple   |     1 |          4 |            |",
        "5 groups from 6 rows",
    ]


def test_sums_are_exact_decimals_and_an_all_empty_group_is_empty():
    assert lines(["--group-by", "region", "--agg", "sum:price", "--agg", "min:price"]) == [
        "region  sum(price)  min(price)",
        "north         4.50        0.75",
        "south            2           2",
        "east           1.5         1.5",
        "3 groups from 6 rows",
    ]
    assert lines(["--where", "region=south", "--group-by", "product", "--agg", "sum:price"]) == [
        "product  sum(price)",
        "pear              2",
        "apple",
        "2 groups from 2 rows",
    ]


def test_min_and_max_print_the_first_winning_cell_as_written():
    data = "k,v\na,1.5\na,1.50\na,0.5\nb,2\nb,2.0\n"
    assert lines(["--group-by", "k", "--agg", "max:v", "--agg", "min:v", "--agg", "sum:v"], data) == [
        "k  max(v)  min(v)  sum(v)",
        "a     1.5     0.5    3.50",
        "b       2       2     4.0",
        "2 groups from 5 rows",
    ]


def test_only_rows_kept_by_where_are_read():
    data = "region,units\nnorth,2\nwest,n/a\nnorth,3\n"
    assert lines(["--where", "region=north", "--group-by", "region", "--agg", "sum:units"], data) == [
        "region  sum(units)",
        "north            5",
        "1 group from 2 rows",
    ]


def test_sorting_groups_by_an_aggregate_keeps_ties_in_first_appearance_order():
    argv = ["--group-by", "region,product"]
    assert keys(lines(argv + ["--sort", "-count"]), 2) == [
        ("north", "apple"), ("south", "pear"), ("north", "pear"), ("east", "apple"), ("south", "apple")]
    assert keys(lines(argv + ["--sort", "count"]), 2) == [
        ("south", "pear"), ("north", "pear"), ("east", "apple"), ("south", "apple"), ("north", "apple")]


def test_sorting_groups_follows_the_sort_rules_and_names_output_columns():
    argv = ["--group-by", "region,product", "--agg", "sum:units"]
    assert keys(lines(argv + ["--sort", "sum(units)"]), 2) == [
        ("east", "apple"), ("north", "apple"), ("south", "apple"), ("north", "pear"), ("south", "pear")]
    assert keys(lines(argv + ["--sort", "-sum(units)"]), 2) == [
        ("north", "pear"), ("north", "apple"), ("south", "apple"), ("east", "apple"), ("south", "pear")]
    assert keys(lines(argv + ["--sort", "-region"]), 2) == [
        ("south", "pear"), ("south", "apple"), ("north", "apple"), ("north", "pear"), ("east", "apple")]
    usage_error(argv + ["--sort", "units"], "unknown field: units")
    usage_error(["--group-by", "product", "--sort", "region"], "unknown field: region")


def test_limit_after_sort_keeps_rows_tied_with_the_last_one():
    argv = ["--group-by", "region,product", "--agg", "sum:units", "--sort", "sum(units)"]
    out = lines(argv + ["--limit", "2"])
    assert keys(out, 2) == [("east", "apple"), ("north", "apple"), ("south", "apple")]
    assert out[-1] == "3 of 5 groups from 6 rows"
    assert lines(argv + ["--limit", "1"])[-1] == "1 of 5 groups from 6 rows"
    out = lines(["--group-by", "region,product", "--agg", "sum:units", "--sort", "-sum(units)", "--limit", "4"])
    assert keys(out, 2)[-1] == ("east", "apple") and out[-1] == "4 of 5 groups from 6 rows"


def test_limit_ties_on_empty_cells_and_ungrouped_rows():
    data = "k,v\na,1\nb,\nc,\nd,2\n"
    out = lines(["--sort", "v", "--limit", "3"], data)
    assert [line.split()[0] for line in out[1:-1]] == ["a", "d", "b", "c"]
    assert out[-1] == "4 rows"
    assert lines(["--sort", "v", "--limit", "2"], data)[-1] == "2 of 4 rows"


def test_limit_without_sort_keeps_exactly_n():
    out = lines(["--limit", "2"])
    assert [line.split()[0] for line in out[1:-1]] == ["north", "south"]
    assert out[-1] == "2 of 6 rows"
    assert lines(["--group-by", "region", "--limit", "2"])[-1] == "2 of 3 groups from 6 rows"
    assert lines(["--group-by", "region", "--limit", "3"])[-1] == "3 groups from 6 rows"
    assert lines(["--limit", "99"])[-1] == "6 rows"


def test_invalid_limit_values():
    for value in ["0", "-1", "1.5", "", "+2", " 2", "two", "٣"]:
        usage_error(["--limit", value], f"invalid --limit value: {value}")


def test_group_by_errors():
    for value in ["", "region,", ",region", "region,region", "region,product,units"]:
        usage_error(["--group-by", value], f"invalid --group-by value: {value}")
    usage_error(["--group-by", "region,colour"], "unknown field: colour")


def test_agg_errors():
    for value in ["avg:units", "count:units", "sum", "sum:", "SUM:units", "min"]:
        usage_error(["--group-by", "region", "--agg", value], f"invalid --agg value: {value}")
    usage_error(["--group-by", "region", "--agg", "max:colour"], "unknown field: colour")
    usage_error(["--agg", "count"], "--agg needs --group-by")


def test_non_numeric_cell_names_the_field_and_line():
    data = "region,units\nnorth,2\nsouth,lots\n"
    usage_error(["--group-by", "region", "--agg", "max:units"], "field units is not numeric: lots (line 3)", data)
    usage_error(["--where", "region=south", "--group-by", "region", "--agg", "sum:region"], "field region is not numeric: south (line 3)", data)


def test_layout_rules_apply_to_grouped_rows():
    assert lines(["--where", "region=west", "--group-by", "region", "--agg", "sum:units", "--format", "markdown"]) == [
        "| region | sum(units) |",
        "| ------ | ---------- |",
        "0 groups from 0 rows",
    ]
    data = "year,amount\n2024,5\n2025,7\n2024,1\n"
    assert lines(["--group-by", "year", "--agg", "sum:amount", "--format", "markdown"], data) == [
        "| year | sum(amount) |",
        "| ---: | ----------: |",
        "| 2024 |           6 |",
        "| 2025 |           7 |",
        "2 groups from 3 rows",
    ]
