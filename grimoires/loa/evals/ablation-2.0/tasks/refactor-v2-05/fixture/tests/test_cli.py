from semverkit.cli import main


def test_cli_parse(capsys):
    assert main(["parse", "v1.2.3+b"]) == 0
    assert capsys.readouterr().out == "1.2.3+b\n"


def test_cli_parse_error(capsys):
    assert main(["parse", "1.2"]) == 2
    assert capsys.readouterr().err == "error: invalid version: '1.2'\n"


def test_cli_sort_and_bump(capsys):
    assert main(["sort", "1.0.0", "1.0.0-a", "0.1.0"]) == 0
    assert main(["bump", "1.2.3", "prerelease", "--id", "rc"]) == 0
    assert capsys.readouterr().out == "0.1.0\n1.0.0-a\n1.0.0\n1.2.4-rc.0\n"


def test_cli_test_and_max(capsys):
    assert main(["test", "1.0.0", "^1"]) == 0
    assert main(["test", "2.0.0", "^1"]) == 1
    assert main(["max", "~1.2", "1.2.0", "1.2.9", "1.3.0"]) == 0
    assert main(["max", "9", "1.2.0"]) == 1
    assert capsys.readouterr().out == "yes\nno\n1.2.9\nnone\n"


def test_cli_errors_go_to_stderr(capsys):
    assert main(["bump", "1.0.0", "huge"]) == 2
    assert main(["normalize", "1.x-a"]) == 2
    err = capsys.readouterr().err
    assert err == "error: unknown part: 'huge'\nerror: invalid comparator: '1.x-a'\n"


def test_cli_table_and_normalize(capsys):
    assert main(["table", "--range", "^0.1", "0.1.5", "0.2.0"]) == 0
    assert main(["normalize", "~0.1"]) == 0
    assert capsys.readouterr().out == "version  ^0.1\n-------  ----\n0.1.5    yes\n0.2.0    no\n>=0.1.0 <0.2.0-0\n"
