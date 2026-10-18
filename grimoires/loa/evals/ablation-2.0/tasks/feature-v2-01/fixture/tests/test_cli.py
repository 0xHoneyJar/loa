from helpers import run_cli, write_config


def test_apply_in_order():
    code, out, err = run_cli(["--apply", "strip,upper,rev"], "  abc \n x\n")
    assert (code, out, err) == (0, "CBA\nX\n", "")


def test_no_filters_passes_lines_through():
    assert run_cli([], "a\n b\n") == (0, "a\n b\n", "")


def test_squeeze_and_number():
    code, out, _ = run_cli(["--apply", "squeeze", "--number"], "a  b\n\tc\n")
    assert code == 0 and out == "1: a b\n2:  c\n"


def test_skip_blank_counts_after_filtering():
    code, out, _ = run_cli(["--apply", "strip", "--skip-blank", "--number"], "a\n   \nb\n")
    assert out == "1: a\n2: b\n"


def test_list_builtins():
    code, out, err = run_cli(["--list"])
    assert code == 0 and err == ""
    assert out == (
        "lower    lowercase the line\n"
        "rev      reverse the characters of the line\n"
        "squeeze  collapse each run of whitespace to one space\n"
        "strip    remove leading and trailing whitespace\n"
        "upper    uppercase the line\n"
    )


def test_unknown_filter_is_a_usage_error():
    assert run_cli(["--apply", "upper,nope"], "x\n") == (2, "", "textpipe: unknown filter: nope\n")


def test_bad_apply_value():
    assert run_cli(["--apply", "upper,,lower"]) == (2, "", "textpipe: invalid --apply value: upper,,lower\n")


def test_unknown_option_and_missing_value():
    assert run_cli(["--frob"])[2] == "textpipe: unknown option: --frob\n"
    assert run_cli(["--apply"])[2] == "textpipe: --apply needs a value\n"


def test_reads_a_file(tmp_path):
    path = tmp_path / "in.txt"
    path.write_text("Hi\n", encoding="utf-8")
    assert run_cli(["--apply", "lower", str(path)]) == (0, "hi\n", "")
    assert run_cli([str(tmp_path / "missing.txt")])[0] == 2
