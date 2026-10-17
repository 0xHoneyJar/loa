from taskgraph.cli import main

MANIFEST = "a: 1h\nb: 30m needs a\nc: 2h\n"


def write(tmp_path, text):
    path = tmp_path / "plan.txt"
    path.write_text(text, encoding="utf-8")
    return str(path)


def test_cli_order_levels_critical(tmp_path, capsys):
    path = write(tmp_path, MANIFEST)
    assert main(["order", path]) == 0
    assert main(["levels", path]) == 0
    assert main(["critical", path]) == 0
    assert main(["check", path]) == 0
    assert capsys.readouterr().out == "a\nb\nc\n0: a c\n1: b\n2h: c\nok: 3 tasks\n"


def test_cli_schedule(tmp_path, capsys):
    path = write(tmp_path, MANIFEST)
    assert main(["schedule", path, "--workers", "1"]) == 0
    out = capsys.readouterr().out
    assert out.splitlines()[:3] == ["a  0-60    w1", "b  60-90   w1", "c  90-210  w1"]
    assert "makespan: 3h30m" in out


def test_cli_errors(tmp_path, capsys):
    path = write(tmp_path, "a: 1 needs a\n")
    assert main(["check", path]) == 2
    assert main(["order", str(tmp_path / "missing.txt")]) == 2
    err = capsys.readouterr().err.splitlines()
    assert err == ["error: cycle: a -> a", f"error: cannot read {str(tmp_path / 'missing.txt')!r}"]


def test_cli_slack_and_dot(tmp_path, capsys):
    path = write(tmp_path, MANIFEST)
    assert main(["slack", path]) == 0
    assert main(["dot", path]) == 0
    out = capsys.readouterr().out
    assert out.startswith("a 30m\nb 30m\nc 0m\ndigraph tasks {\n")
