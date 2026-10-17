import io
import json
import os

from docstore import cli


def run(root, *args):
    out, err = io.StringIO(), io.StringIO()
    code = cli.main(["--root", str(root), *args], stdout=out, stderr=err)
    return code, out.getvalue(), err.getvalue()


def write(tmp_path, name, value):
    path = tmp_path / name
    path.write_text(value if isinstance(value, str) else json.dumps(value))
    return str(path)


def test_create_show_list(tmp_path):
    f = write(tmp_path, "d.json", {"b": 1, "a": 2})
    assert run(tmp_path, "create", "doc1", f) == (0, "rev 1\n", "")
    assert run(tmp_path, "show", "doc1") == (0, '{"a":2,"b":1}\n', "")
    assert run(tmp_path, "list") == (0, "doc1 1\n", "")
    assert os.path.exists(tmp_path / "docs" / "doc1.json")


def test_put_with_rev_conflict(tmp_path):
    f = write(tmp_path, "d.json", {})
    run(tmp_path, "create", "d", f)
    assert run(tmp_path, "put", "d", f, "--rev", "1") == (0, "rev 2\n", "")
    code, out, err = run(tmp_path, "put", "d", f, "--rev", "1")
    assert (code, out) == (4, "")
    assert err == "docstore: revision mismatch for 'd': expected 1, found 2\n"


def test_errors_and_exit_codes(tmp_path):
    assert run(tmp_path, "show", "nope")[0] == 3
    bad = write(tmp_path, "bad.json", "[1]")
    assert run(tmp_path, "create", "x", bad) == (5, "", "docstore: document root must be an object\n")
    broken = write(tmp_path, "broken.json", "{")
    code, _, err = run(tmp_path, "create", "x", broken)
    assert code == 5 and err.startswith(f"docstore: {broken}: invalid JSON:")
    assert run(tmp_path, "show", "BAD") == (1, "", "docstore: invalid document id: 'BAD'\n")


def test_usage_errors(tmp_path):
    code, out, err = run(tmp_path)
    assert (code, out) == (2, "") and err.startswith("docstore: usage:")
    assert run(tmp_path, "frobnicate")[0] == 2


def test_select_find_history(tmp_path):
    run(tmp_path, "create", "a", write(tmp_path, "a.json", {"t": ["x", {"k": None}]}))
    assert run(tmp_path, "select", "a", "t.1.k") == (0, "null\n", "")
    assert run(tmp_path, "find", "t.0", '"x"') == (0, "a\n", "")
    code, out, _ = run(tmp_path, "history", "a")
    assert code == 0 and out.split("\t")[:4] == ["1", "a", "create", "1"]
    assert (tmp_path / "history.log").read_text().count("\n") == 1


def test_config_file(tmp_path):
    (tmp_path / "docstore.conf").write_text("max_bytes = 10\nhistory_file = h.txt\n")
    big = write(tmp_path, "big.json", {"abcdefgh": 1})
    code, _, err = run(tmp_path, "create", "a", big)
    assert code == 5 and "limit 10" in err
    run(tmp_path, "create", "a", write(tmp_path, "s.json", {}))
    assert (tmp_path / "h.txt").exists()


def test_export_import_stats(tmp_path):
    src, dst = tmp_path / "src", tmp_path / "dst"
    run(src, "create", "a", write(tmp_path, "a.json", {"x": [[1]]}))
    code, bundle, _ = run(src, "export")
    assert code == 0
    b = write(tmp_path, "bundle.json", bundle)
    assert run(dst, "import", b) == (0, "imported 1\n", "")
    assert run(dst, "import", b)[0] == 1
    assert run(dst, "stats") == (0, "documents 1\nbytes 11\nmax_depth 3\nlargest a\n", "")
