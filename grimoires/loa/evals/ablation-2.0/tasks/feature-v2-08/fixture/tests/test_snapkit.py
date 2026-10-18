import io
import os

import pytest

from snapkit import cli, paths, sizes
from snapkit.config import Config, load_config, parse_config
from snapkit.diff import diff_snapshots, format_diff
from snapkit.errors import ConfigError, PathError, SnapshotError
from snapkit.report import format_du
from snapkit.snapshot import build_snapshot, format_snapshot, parse_snapshot
from snapkit.walker import files, walk


def make(root, spec):
    """spec: {relpath: text or None (directory)}"""
    for rel, content in spec.items():
        p = os.path.join(root, *rel.split("/"))
        if content is None:
            os.makedirs(p, exist_ok=True)
        else:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(content)


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    code = cli.main(list(argv), out, err)
    return code, out.getvalue(), err.getvalue()


def test_normalize_drops_dots_and_slashes():
    assert paths.normalize("./a//b/./c/") == "a/b/c"
    assert paths.normalize("x") == "x"


@pytest.mark.parametrize("bad, msg", [
    ("/a", "absolute path not allowed: '/a'"),
    ("a/../b", "'..' not allowed: 'a/../b'"),
    ("./", "empty path: './'"),
])
def test_normalize_errors(bad, msg):
    with pytest.raises(PathError) as exc:
        paths.normalize(bad)
    assert str(exc.value) == msg


def test_ancestors_and_depth():
    assert paths.ancestors("a/b/c") == ["a", "a/b"]
    assert paths.ancestors("a") == []
    assert paths.depth("") == 0 and paths.depth("a/b") == 2


def test_config_defaults_and_keys():
    c = parse_config("# comment\n\nexclude = a, b/c/\nexclude=d\nblock_size = 512\ndigest_length = 8\n")
    assert c.exclude == ["a", "b/c", "d"]
    assert c.block_size == 512 and c.digest_length == 8
    d = parse_config("")
    assert d.exclude == [] and d.block_size == 4096 and d.digest_length == 16


@pytest.mark.parametrize("text, msg", [
    ("colour = red\n", "snapkit.conf:1: unknown key 'colour'"),
    ("\nblock_size = 0\n", "snapkit.conf:2: block_size must be an integer at least 1"),
    ("digest_length = 99\n", "snapkit.conf:1: digest_length must be an integer from 8 to 64"),
    ("exclude\n", "snapkit.conf:1: expected key = value"),
    ("exclude = ../x\n", "snapkit.conf:1: '..' not allowed: '../x'"),
])
def test_config_errors(text, msg):
    with pytest.raises(ConfigError) as exc:
        parse_config(text)
    assert str(exc.value) == msg


def test_load_config_finds_the_root_file(tmp_path):
    make(tmp_path, {"snapkit.conf": "exclude = tmp\n"})
    assert load_config(str(tmp_path)).exclude == ["tmp"]
    assert load_config(str(tmp_path / "nowhere")).exclude == []


def test_walk_order_and_exclusions(tmp_path):
    make(tmp_path, {"b.txt": "b", "a/x": "xx", "a/y/z": "z", "c": None, "skip/me": "m"})
    entries = list(walk(str(tmp_path), Config(exclude=["skip", "a/x"])))
    assert [(e.path, e.kind) for e in entries] == [
        ("a", "dir"), ("a/y", "dir"), ("a/y/z", "file"), ("b.txt", "file"), ("c", "dir")]


def test_walk_skips_symlinks(tmp_path):
    make(tmp_path, {"real": "r"})
    os.symlink("real", tmp_path / "link")
    assert [e.path for e in files(str(tmp_path), Config())] == ["real"]


def test_snapshot_text_and_round_trip(tmp_path):
    make(tmp_path, {"a b.txt": "hello", "d/e": "", "d.txt": "123"})
    snap = build_snapshot(str(tmp_path), Config(digest_length=8))
    text = format_snapshot(snap)
    lines = text.splitlines()
    assert lines[0] == "snapkit-snapshot 1"
    assert [l.split(" ", 2)[2] for l in lines[1:-1]] == ["a b.txt", "d.txt", "d/e"]
    assert lines[1].split(" ")[:2] == ["2cf24dba", "5"]
    assert lines[-1] == "total 3 files 8 bytes"
    assert parse_snapshot(text).records == snap.records


@pytest.mark.parametrize("text, msg", [
    ("nope\n", "s: not a snapkit snapshot"),
    ("snapkit-snapshot 1\nabc x y\ntotal 0 files 0 bytes\n", "s:2: malformed record"),
    ("snapkit-snapshot 1\n", "s: missing total line"),
    ("snapkit-snapshot 1\ntotal 0 files 0 bytes\nextra\n", "s:3: text after the total line"),
    ("snapkit-snapshot 1\nab 1 x\nab 1 x\ntotal 2 files 2 bytes\n", "s: duplicate path"),
])
def test_parse_snapshot_errors(text, msg):
    with pytest.raises(SnapshotError) as exc:
        parse_snapshot(text, "s")
    assert str(exc.value) == msg


def test_diff_codes_and_summary(tmp_path):
    make(tmp_path, {"keep": "k", "gone": "g", "edit": "1"})
    old = build_snapshot(str(tmp_path), Config())
    os.remove(tmp_path / "gone")
    make(tmp_path, {"edit": "2", "new/f": "n"})
    new = build_snapshot(str(tmp_path), Config())
    changes = diff_snapshots(old, new)
    assert changes == [("M", "edit"), ("D", "gone"), ("A", "new/f")]
    assert format_diff(changes).splitlines()[-1] == "1 added, 1 deleted, 1 modified"


def test_blocks_and_human():
    assert sizes.blocks(0, 4096) == 0 and sizes.blocks(1, 4096) == 4096 and sizes.blocks(4097, 4096) == 8192
    assert sizes.human(1023) == "1023B" and sizes.human(1536) == "1.5K" and sizes.human(3 * 1024 ** 2) == "3.0M"


def test_du_totals_and_format(tmp_path):
    make(tmp_path, {"a/x": "x" * 10, "a/b/y": "y", "c": "cc", "e": None})
    totals = sizes.directory_totals(walk(str(tmp_path), Config()), 100)
    assert totals == {"": 300, "a": 200, "a/b": 100, "e": 0}
    assert format_du(totals) == "100\ta/b\n200\ta\n0\te\n300\t.\n"
    assert format_du(totals, max_depth=1) == "200\ta\n0\te\n300\t.\n"


def test_cli_snapshot_honours_config_exclude(tmp_path):
    make(tmp_path, {"snapkit.conf": "exclude = logs, snapkit.conf\ndigest_length = 8\n",
                    "logs/a": "a", "src/m.py": "pass\n"})
    code, out, err = run("snapshot", "--root", str(tmp_path))
    assert code == 0 and err == ""
    assert out.splitlines()[1:] == [out.splitlines()[1], "total 1 files 5 bytes"]
    assert out.splitlines()[1].endswith(" 5 src/m.py")


def test_cli_snapshot_output_file_and_diff(tmp_path):
    make(tmp_path, {"t/one": "1"})
    s1, s2 = tmp_path / "s1", tmp_path / "s2"
    assert run("snapshot", "--root", str(tmp_path / "t"), "--output", str(s1))[0] == 0
    make(tmp_path, {"t/two": "2"})
    assert run("snapshot", "--root", str(tmp_path / "t"), "--output", str(s2))[0] == 0
    assert run("diff", str(s1), str(s1)) == (0, "0 added, 0 deleted, 0 modified\n", "")
    assert run("diff", str(s1), str(s2)) == (1, "A two\n1 added, 0 deleted, 0 modified\n", "")


def test_cli_du_human_and_depth(tmp_path):
    make(tmp_path, {"d/f": "x", "g": "y"})
    code, out, _ = run("du", "--root", str(tmp_path), "--human", "--depth", "0")
    assert code == 0 and out == "8.0K\t.\n"


def test_cli_errors(tmp_path):
    code, _, err = run("snapshot", "--bogus")
    assert code == 2 and err.startswith("snapkit: unknown option --bogus\nusage:")
    code, _, err = run("diff", str(tmp_path / "missing"), str(tmp_path / "missing"))
    assert code == 2 and err == f"snapkit: {tmp_path / 'missing'}: cannot read\n"
    make(tmp_path, {"snapkit.conf": "size = 1\n"})
    code, _, err = run("du", "--root", str(tmp_path))
    assert (code, err) == (2, "snapkit: snapkit.conf:1: unknown key 'size'\n")
    assert run()[0] == 2 and run("frobnicate")[0] == 2
