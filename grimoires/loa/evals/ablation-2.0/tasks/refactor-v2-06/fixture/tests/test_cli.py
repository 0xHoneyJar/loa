from cronplan.cli import main


def test_cli_next(capsys):
    assert main(["next", "0 9 * * 1-5", "--after", "2026-10-16T10:00", "--count", "2"]) == 0
    assert capsys.readouterr().out == "2026-10-19T09:00\n2026-10-20T09:00\n"


def test_cli_normalize_and_check(capsys):
    assert main(["normalize", "0,1,2 * * * *"]) == 0
    assert main(["check", "@daily"]) == 0
    assert capsys.readouterr().out == "0-2 * * * *\nok\n"


def test_cli_errors(capsys):
    assert main(["check", "61 * * * *"]) == 2
    assert main(["next", "* * * * *", "--after", "yesterday"]) == 2
    assert main(["month", "* * * * *", "2026/10"]) == 2
    assert capsys.readouterr().err == (
        "error: field 'minute': value 61 out of range 0-59\n"
        "error: bad datetime: 'yesterday'\n"
        "error: bad month: '2026/10'\n")


def test_cli_month(capsys):
    assert main(["month", "0 0 29 2 *", "2028-02"]) == 0
    assert capsys.readouterr().out == "2028-02-29  1\ntotal  1\n"
