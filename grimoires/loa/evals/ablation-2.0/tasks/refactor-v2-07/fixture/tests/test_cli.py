import json

from patchwork.cli import main


def write(tmp_path, name, value):
    path = tmp_path / name
    path.write_text(json.dumps(value), encoding="utf-8")
    return str(path)


def test_cli_apply(tmp_path, capsys):
    doc = write(tmp_path, "doc.json", {"b": 1})
    patch = write(tmp_path, "patch.json", [{"op": "add", "path": "/a", "value": [1]}])
    assert main(["apply", doc, patch]) == 0
    assert json.loads(capsys.readouterr().out) == {"a": [1], "b": 1}


def test_cli_get_and_diff(tmp_path, capsys):
    doc = write(tmp_path, "doc.json", {"a": {"b": [1, 2]}})
    other = write(tmp_path, "other.json", {"a": {"b": [1, 3]}})
    assert main(["get", doc, "/a/b"]) == 0
    assert main(["diff", doc, other]) == 0
    out = capsys.readouterr().out
    assert out.startswith("[1, 2]\n")
    assert json.loads(out[len("[1, 2]\n"):]) == [{"op": "replace", "path": "/a/b/1", "value": 3}]


def test_cli_errors(tmp_path, capsys):
    bad = tmp_path / "bad.json"
    bad.write_text("{nope", encoding="utf-8")
    doc = write(tmp_path, "doc.json", {})
    assert main(["explain", str(bad)]) == 2
    assert main(["get", doc, "/x"]) == 2
    assert main(["explain", str(tmp_path / "missing.json")]) == 2
    err = capsys.readouterr().err.splitlines()
    assert err[0] == f"error: bad json in {str(bad)!r}"
    assert err[1] == "error: path not found: '/x'"
    assert err[2] == f"error: cannot read {str(tmp_path / 'missing.json')!r}"


def test_cli_paths_and_types(tmp_path, capsys):
    doc = write(tmp_path, "doc.json", {"a": [True]})
    assert main(["paths", doc]) == 0
    assert main(["types", doc]) == 0
    assert capsys.readouterr().out == "(root)\n/a\n/a/0\nobject 1\narray 1\nboolean 1\n"
