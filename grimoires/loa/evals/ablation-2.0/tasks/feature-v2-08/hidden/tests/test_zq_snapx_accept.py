import importlib
import io
import os

import pytest

from snapkit import cli, errors


def mod(name):
    return importlib.import_module("snapkit." + name)


def m(pattern, path, casefold=False):
    return mod("glob").match(pattern, path, casefold)


def glob_error(pattern):
    with pytest.raises(errors.GlobError) as exc:
        mod("glob").Glob(pattern)
    assert isinstance(exc.value, errors.SnapError)
    return str(exc.value)


def expand(text):
    return mod("braces").expand(text)


def rules(text, source="r", base=""):
    return mod("rules").parse_rules(text, source, base)


def rule(text, source="r", base=""):
    got = rules(text, source, base)
    assert len(got) == 1
    return got[0]


def rule_error(text, source="r"):
    with pytest.raises(errors.RuleError) as exc:
        rules(text, source)
    assert isinstance(exc.value, errors.SnapError)
    return str(exc.value)


def ignore(files, casefold=False, fixed=()):
    ig = mod("ignore").IgnoreRules(casefold=casefold, fixed=fixed)
    for base, text in files:
        src = ".snapignore" if base == "" else base + "/.snapignore"
        ig.add_file(base, rules(text, src, base))
    return ig


def decided(ig, path, is_dir=False):
    d = ig.check(path, is_dir)
    return d.excluded, (None if d.rule is None else (d.rule.source, d.rule.line))


def make(root, spec):
    for rel, content in spec.items():
        p = os.path.join(str(root), *rel.split("/"))
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


def listed(out):
    return [line.split(" ", 2)[2] for line in out.splitlines()[1:-1]]



TREE = {
    ".snapignore": "*.log\nbuild/\n!important.log\n/src/.snapignore\n",
    "important.log": "i",
    "app.log": "a",
    "readme": "r",
    "build/.snapignore": "[z-a]\n",
    "build/out.bin": "b",
    "lib/build": "not a directory",
    "src/.snapignore": "!debug.log\n/gen/\nnotes/\n",
    "src/debug.log": "d",
    "src/main.c": "m",
    "src/gen/g.c": "g",
    "src/sub/gen/k.c": "k",
    "src/sub/notes/n": "n",
    "notes/n": "top",
}

def test_star_question_dots_and_escapes():
    assert m("*.py", "a.py") and m("*.py", ".py") and not m("*.py", "a/b.py")
    assert m("*/*.py", "a/b.py") and not m("*/*.py", "a/b/c.py")
    assert m("?.txt", "a.txt") and not m("?.txt", "ab.txt") and not m("?.txt", ".txt")
    assert m("a*b*c", "abc") and m("a*b*c", "aXbYbc") and not m("a*b*c", "acb")
    assert not m("a?b", "a/b")
    assert m("*", ".env") and m("?bc", ".bc") and m(".*", ".x") and m("*/*", ".a/.b")
    assert m(r"\*", "*") and not m(r"\*", "a")
    assert m(r"\?", "?") and not m(r"\?", "x")
    assert m(r"\[a]", "[a]") and not m(r"\[a]", "a")
    assert m(r"a\\b", "a\\b") and m(r"\a\b", "ab")


def test_trailing_backslashes_and_slash_splitting():
    assert glob_error("a\\") == r"trailing backslash in pattern 'a\\'"
    assert glob_error("ok/a\\\\\\") == "trailing backslash in pattern " + repr("ok/a\\\\\\")
    assert glob_error("a\\/b") == "trailing backslash in pattern " + repr("a\\/b")
    assert m("a\\\\", "a\\")
    assert m("[a\\\\]", "\\")
    assert not m("a[/]b", "a/b")
    assert m("a[/]b", "a[/]b")
    assert not m("a", "a/b") and not m("a/b", "a")


def test_globstar_segments():
    assert m("**/x", "x") and m("**/x", "a/b/x") and not m("**/x", "a/xx")
    assert m("a/**/b", "a/b") and m("a/**/b", "a/q/r/b") and not m("a/**/b", "a/q/r")
    assert m("a/**", "a/b") and m("a/**", "a/b/c") and not m("a/**", "a")
    assert m("**", "a") and m("**", "a/b/c")
    assert m("**/**", "a") and m("**/a/**", "a/b") and not m("**/a/**", "b/a")
    assert m("a**b", "ab") and m("a**b", "axyb") and not m("a**b", "ax/yb")
    assert m("**x", "abx") and not m("**x", "a/x")
    assert m(r"\*\*", "**") and not m(r"\*\*", "ab")
    assert not m(r"\*\*/x", "a/x") and m(r"\*\*/x", "**/x")
    assert not m("x/**y", "x/a/y")


def test_bracket_members_negation_and_close_first():
    assert m("[abc]", "b") and not m("[abc]", "d") and not m("[abc]", "ab")
    assert m("[!abc]", "d") and not m("[!abc]", "a")
    assert m("[^abc]", "d") and not m("[^abc]", "c")
    assert m("x[0-9][0-9]", "x42") and not m("x[0-9][0-9]", "x4")
    assert m("[]a]", "]") and m("[]a]", "a") and not m("[]a]", "b")
    assert not m("[!]a]", "]") and not m("[!]a]", "a") and m("[!]a]", "b")
    assert m("[^]]", "x") and not m("[^]]", "]")
    assert m("[]-a]", "^")


def test_unterminated_brackets_dashes_and_code_points():
    assert m("[ab", "[ab") and not m("[ab", "a")
    assert m("[]", "[]") and m("[!]", "[!]")
    assert m(r"[a\]", "[a]") and not m(r"[a\]", "a")
    assert m("[*", "[xyz") and m("x[", "x[")
    assert m("[z-a", "[z-a")
    for pat in ("[a-]", "[-a]", r"[\-a]"):
        assert m(pat, "a") and m(pat, "-") and not m(pat, "b"), pat
    assert m("[a-c-e]", "b") and m("[a-c-e]", "-") and m("[a-c-e]", "e") and not m("[a-c-e]", "d")
    assert m("[--0]", ".") and m("[--0]", "0") and not m("[--0]", "1")
    assert m(r"[a-\z]", "q") and m(r"[\a-z]", "q")
    assert m("[Z-a]", "_") and m("[Z-a]", "`") and not m("[Z-a]", "b") and not m("[Z-a]", "Y")
    assert m("[!--0]", "a") and not m("[!--0]", ".")


def test_classes_and_class_tokens():
    assert m("[[:alpha:]]", "Q") and not m("[[:alpha:]]", "1")
    assert m("[[:digit:]]", "7") and not m("[[:digit:]]", "a")
    assert m("[[:alnum:]]", "z") and m("[[:alnum:]]", "0") and not m("[[:alnum:]]", "_")
    assert m("[[:upper:]]", "A") and not m("[[:upper:]]", "a")
    assert m("[[:lower:]]", "a") and not m("[[:lower:]]", "A")
    assert m("[[:space:]]", "\t") and m("[[:space:]]", " ") and m("[[:space:]]", "\v") and not m("[[:space:]]", "_")
    assert all(m("[[:punct:]]", c) for c in "!\"#$%&'()*+,-.:;<=>?@[\\]^_`{|}~")
    assert not m("[[:punct:]]", "a") and not m("[[:alpha:]]", "é")
    assert m("[![:digit:]x]", "a") and not m("[![:digit:]x]", "x") and not m("[![:digit:]x]", "3")
    assert m("[a-[:digit:]]", "5") and m("[a-[:digit:]]", "-") and m("[a-[:digit:]]", "a")
    assert not m("[a-[:digit:]]", "b")
    assert m("[[:alpha:]-z]", "-") and m("[[:alpha:]-z]", "Q") and not m("[[:alpha:]-z]", "1")
    assert m("[[:alp]", ":") and m("[[:alp]", "p") and m("[[:alp]", "[") and not m("[[:alp]", "h")
    assert m("[[:]", "[") and m("[[:]", ":")


def test_bracket_errors_and_their_order():
    assert glob_error("[z-a]") == "invalid range 'z'-'a' in pattern '[z-a]'"
    assert glob_error(r"x/[\z-a]") == "invalid range 'z'-'a' in pattern " + repr(r"x/[\z-a]")
    assert glob_error("[a--]") == "invalid range 'a'-'-' in pattern '[a--]'"
    assert glob_error("[[:foo:]]") == "unknown class 'foo' in pattern '[[:foo:]]'"
    assert m("[[:Alpha:]]", "A]") and not m("[[:Alpha:]]", "A")
    assert glob_error("[z-a]/b\\") == "trailing backslash in pattern " + repr("[z-a]/b\\")
    assert glob_error("[[:foo:]][z-a]") == "unknown class 'foo' in pattern '[[:foo:]][z-a]'"
    assert glob_error("[z-a][[:foo:]]") == "invalid range 'z'-'a' in pattern '[z-a][[:foo:]]'"
    assert glob_error("[[:foo:]z-a]") == "unknown class 'foo' in pattern '[[:foo:]z-a]'"
    assert glob_error("a/[z-a]/[[:x:]]") == "invalid range 'z'-'a' in pattern 'a/[z-a]/[[:x:]]'"
    assert m("[z-a", "[z-a") and m("[[:foo:]", "[o") and not m("[[:foo:]", "[[:foo:]")


def test_casefold():
    assert not m("README", "readme") and m("README", "readme", True)
    assert m("[A-C]x", "bX", True) and not m("[A-C]x", "bX")
    assert m("[[:upper:]]", "q", True) and m("[[:lower:]]", "Q", True)
    assert not m("[!a]", "A", True) and m("[!a]", "A")
    assert not m("[!A-Z]", "q", True) and m("[!A-Z]", "q")
    assert m("[Z-a]", "z", True) and not m("[Z-a]", "z")
    assert not m("É", "é", True)
    assert m("É", "É", True)
    assert not m("[[:alpha:]]", "é", True)


def test_rule_lines():
    r = rule("!/doc/build/\n", "sub/.snapignore", "sub")
    assert (r.source, r.line, r.text, r.negated, r.dir_only, r.anchored, r.pattern, r.base) == (
        "sub/.snapignore", 1, "!/doc/build/", True, True, True, "doc/build", "sub")
    r = rule("a//", "x")
    assert (r.text, r.negated, r.dir_only, r.anchored, r.pattern, r.base) == ("a//", False, True, False, "a", "")
    r = rule("/**/x", "x")
    assert (r.anchored, r.pattern) == (True, "**/x")
    got = rules("# c\n\n\\#x\n\\!y\n #z\n!#w\n!!v\n", "f")
    assert [(r.line, r.text, r.negated, r.pattern) for r in got] == [
        (3, "\\#x", False, "\\#x"), (4, "\\!y", False, "\\!y"), (5, " #z", False, " #z"),
        (6, "!#w", True, "#w"), (7, "!!v", True, "!v")]
    assert got[0].matches("#x", False) and got[1].matches("!y", False) and got[2].matches(" #z", False)
    assert got[4].matches("!v", False)
    assert rule("a  \n").text == "a"
    assert rule("a\\ \n").text == "a\\ " and rule("a\\ \n").matches("a ", False)
    assert rule("a\\\\ \n").text == "a\\\\" and rule("a\\\\ \n").matches("a\\", False)
    assert rule("a\\  \n").text == "a\\ "
    assert rule("a\\\\\\ \n").text == "a\\\\\\ "
    assert rule("a\t\n").text == "a\t" and rule("  a").text == "  a"
    assert rules("   \n", "f") == []
    got = rules("a\r\nb\r\n\r\nc\r\r\n", "f")
    assert [(r.line, r.text) for r in got] == [(1, "a"), (2, "b"), (4, "c\r")]
    assert rule("d \r\n").text == "d"


def test_rule_line_errors():
    assert rule_error("ok\n!\n", "f") == "f:2: empty pattern"
    assert rule_error("/\n", "f") == "f:1: empty pattern"
    assert rule_error("# c\n!//\n", "s/.snapignore") == "s/.snapignore:2: empty pattern"
    assert rule_error("!  \n", "f") == "f:1: empty pattern"
    assert rule_error("ok\n[z-a]\n[[:x:]]\n", "f") == "f:2: invalid range 'z'-'a' in pattern '[z-a]'"
    assert rule_error("/x\\\n", "f") == "f:1: trailing backslash in pattern " + repr("x\\")
    assert rule_error("!/[[:nope:]]/\n", "f") == "f:1: unknown class 'nope' in pattern '[[:nope:]]'"


def test_dir_only_anchoring_and_bases():
    b = rule("build/")
    assert b.matches("build", True) and b.matches("a/b/build", True)
    assert not b.matches("build", False) and not b.matches("a/build", False)
    f = rule("build")
    assert f.matches("x/build", False) and f.matches("x/build", True)
    d = rule("doc/build")
    assert d.matches("doc/build", False) and not d.matches("x/doc/build", False)
    t = rule("/build")
    assert t.matches("build", True) and not t.matches("a/build", True)
    s = rule("*.o")
    assert s.matches("a/b/c.o", False) and not s.matches("a.o/c", False)
    assert rule("!*.o").matches("x.o", False)
    got = rules("*.o\n/top\nd/x\n", "sub/.snapignore", "sub")
    star, top, dx = got
    assert star.matches("sub/x.o", False) and star.matches("sub/d/x.o", False)
    assert not star.matches("x.o", False) and not star.matches("subx/y.o", False)
    assert not star.matches("sub", True)
    assert top.matches("sub/top", False) and not top.matches("sub/a/top", False) and not top.matches("top", False)
    assert dx.matches("sub/d/x", False) and not dx.matches("sub/q/d/x", False)


def test_last_match_and_excluded_ancestors():
    ig = ignore([("", "*.log\n!keep.log\n")])
    assert decided(ig, "a.log") == (True, (".snapignore", 1))
    assert decided(ig, "d/keep.log") == (False, (".snapignore", 2))
    assert decided(ig, "a.txt") == (False, None)
    ig = ignore([("", "!keep.log\n*.log\n")])
    assert decided(ig, "keep.log") == (True, (".snapignore", 2))
    ig = ignore([("", "cache/\n!cache/keep\n")])
    assert decided(ig, "cache/keep") == (True, (".snapignore", 1))
    assert decided(ig, "cache", True) == (True, (".snapignore", 1))
    ig = ignore([("", "cache/*\n!cache/keep\n")])
    assert decided(ig, "cache/keep") == (False, (".snapignore", 2))
    assert decided(ig, "cache/other") == (True, (".snapignore", 1))
    assert decided(ig, "cache/keep/x") == (False, None)
    ig = ignore([("", "/a/b/\n/a/\n")])
    assert decided(ig, "a/b/c") == (True, (".snapignore", 2))
    ig = ignore([("", "b/\na/\n!a/\n")])
    assert decided(ig, "a/b/c") == (True, (".snapignore", 1))
    assert decided(ig, "a/x") == (False, None)


def test_file_depth_config_entries_and_case():
    files = [("sub/deep", "*.tmp\n"), ("", "*.tmp\n!/sub/deep/z.tmp\n"), ("sub", "!*.tmp\n")]
    ig = ignore(files)
    assert decided(ig, "x.tmp") == (True, (".snapignore", 1))
    assert decided(ig, "sub/x.tmp") == (False, ("sub/.snapignore", 1))
    assert decided(ig, "sub/deep/x.tmp") == (True, ("sub/deep/.snapignore", 1))
    assert decided(ig, "sub/deep/z.tmp") == (True, ("sub/deep/.snapignore", 1))
    assert decided(ig, "sub/other/y.tmp") == (False, ("sub/.snapignore", 1))
    ig = ignore([("", "!a/b\n!**\n")], fixed=["a/b", "x", "x"])
    d = ig.check("a/b", False)
    assert d.excluded and (d.rule.source, d.rule.line, d.rule.text) == ("config", 1, "a/b")
    assert (d.rule.negated, d.rule.dir_only, d.rule.anchored) == (False, False, False)
    assert decided(ig, "a/b/c") == (True, ("config", 1))
    assert decided(ig, "x", True) == (True, ("config", 2))
    assert decided(ig, "a") == (False, (".snapignore", 2))
    assert decided(ig, "a/b2") == (False, (".snapignore", 2))
    folded = ignore([], casefold=True, fixed=["A"])
    assert decided(folded, "a") == (False, None) and decided(folded, "A") == (True, ("config", 1))
    ig = ignore([("", "*.LOG\n!Keep.log\n")], casefold=True)
    assert decided(ig, "a.log") == (True, (".snapignore", 1))
    assert decided(ig, "KEEP.LOG") == (False, (".snapignore", 2))
    assert decided(ignore([("", "*.LOG\n")]), "a.log") == (False, None)


def test_snapshot_and_du_apply_rules_files(tmp_path):
    def part0(tmp_path):
        make(tmp_path, TREE)
        code, out, err = run("snapshot", "--root", str(tmp_path))
        assert (code, err) == (0, "")
        assert listed(out) == [".snapignore", "important.log", "lib/build", "notes/n", "readme",
                               "src/debug.log", "src/main.c", "src/sub/gen/k.c"]
        assert out.splitlines()[-1] == "total 8 files %d bytes" % sum(
            len(TREE[p]) for p in listed(out))

    def part1(tmp_path):
        make(tmp_path, TREE)
        make(tmp_path, {"snapkit.conf": "block_size = 1\nexclude = snapkit.conf\n"})
        code, out, _ = run("du", "--root", str(tmp_path))
        assert code == 0
        rows = dict((line.split("\t")[1], int(line.split("\t")[0])) for line in out.splitlines())
        assert rows["."] == sum(len(TREE[p]) for p in [".snapignore", "important.log", "lib/build", "notes/n",
                                                       "readme", "src/debug.log", "src/main.c", "src/sub/gen/k.c"])
        assert "build" not in rows and "src/gen" not in rows and "src/sub/notes" not in rows
        assert rows["src/sub"] == 1 and rows["src/sub/gen"] == 1

    def part2(tmp_path):
        make(tmp_path, {".snapignore": "skip/\n", "skip/.snapignore": "!\n", "skip/f": "f",
                        "bad/.snapignore": "ok\n\n[[:nope:]]\n", "bad/x": "x"})
        code, out, err = run("snapshot", "--root", str(tmp_path))
        assert code == 2
        assert err == "snapkit: bad/.snapignore:3: unknown class 'nope' in pattern '[[:nope:]]'\n"
        make(tmp_path, {".snapignore": "skip/\nbad\n"})
        code, out, err = run("snapshot", "--root", str(tmp_path))
        assert (code, err) == (0, "") and listed(out) == [".snapignore"]

    (tmp_path / 'p0').mkdir()
    part0(tmp_path / 'p0')
    (tmp_path / 'p1').mkdir()
    part1(tmp_path / 'p1')
    (tmp_path / 'p2').mkdir()
    part2(tmp_path / 'p2')


def test_config_keys(tmp_path):
    make(tmp_path, {"snapkit.conf": "ignore_file = .ignore\nignore_case = yes\n",
                    ".ignore": "*.TMP\nsnapkit.conf\n", ".snapignore": "*\n", "a.tmp": "1", "B.Tmp": "2",
                    "d/.ignore": "!b.tmp\n", "d/b.TMP": "3", "keep": "k"})
    code, out, _ = run("snapshot", "--root", str(tmp_path))
    assert code == 0
    assert listed(out) == [".ignore", ".snapignore", "d/.ignore", "d/b.TMP", "keep"]
    make(tmp_path, {"snapkit.conf": "ignore_case = false\nignore_file = .ignore\n"})
    assert "a.tmp" in listed(run("snapshot", "--root", str(tmp_path))[1])
    config = importlib.import_module("snapkit.config")
    for line, msg in [
        ("ignore_file = a/b", "c:2: ignore_file must be a plain file name"),
        ("ignore_file = ..", "c:2: ignore_file must be a plain file name"),
        ("ignore_file =", "c:2: ignore_file must be a plain file name"),
        ("ignore_case = maybe", "c:2: ignore_case must be yes, no, true or false"),
    ]:
        with pytest.raises(errors.ConfigError) as exc:
            config.parse_config("# x\n" + line + "\n", "c")
        assert str(exc.value) == msg
    ok = config.parse_config("ignore_file = .keep\nignore_case = true\n")
    assert (ok.ignore_file, ok.ignore_case) == (".keep", True)
    assert (config.parse_config("").ignore_file, config.parse_config("").ignore_case) == (".snapignore", False)


def test_check_ignore_lines_status_and_directories(tmp_path):
    def part0(tmp_path):
        make(tmp_path, TREE)
        code, out, err = run("check-ignore", "--root", str(tmp_path), "app.log", "important.log",
                             "./src//debug.log", "readme", "missing/x.log")
        assert (code, err) == (0, "")
        assert out == ("" ".snapignore:1:*.log\tapp.log\n"
                       ".snapignore:3:!important.log\timportant.log\n"
                       "src/.snapignore:1:!debug.log\tsrc/debug.log\n"
                       "::\treadme\n"
                       ".snapignore:1:*.log\tmissing/x.log\n")
        assert run("check-ignore", "--root", str(tmp_path), "readme", "src/debug.log") == (
            1, "::\treadme\nsrc/.snapignore:1:!debug.log\tsrc/debug.log\n", "")

    def part1(tmp_path):
        make(tmp_path, TREE)
        root = str(tmp_path)
        assert run("check-ignore", "--root", root, "lib/build")[1] == "::\tlib/build\n"
        assert run("check-ignore", "--root", root, "lib/build/")[1] == ".snapignore:2:build/\tlib/build\n"
        assert run("check-ignore", "--root", root, "x/build")[1] == "::\tx/build\n"
        assert run("check-ignore", "--root", root, "build")[1] == ".snapignore:2:build/\tbuild\n"
        assert run("check-ignore", "--root", root, "src/sub/notes")[1] == "src/.snapignore:3:notes/\tsrc/sub/notes\n"
        assert run("check-ignore", "--root", root, "src/new/notes")[1] == "::\tsrc/new/notes\n"

    (tmp_path / 'p0').mkdir()
    part0(tmp_path / 'p0')
    (tmp_path / 'p1').mkdir()
    part1(tmp_path / 'p1')


def test_check_ignore_ancestors_config_and_errors(tmp_path):
    def part0(tmp_path):
        make(tmp_path, TREE)
        make(tmp_path, {"snapkit.conf": "exclude = readme, src/sub\n"})
        root = str(tmp_path)
        code, out, err = run("check-ignore", "--root", root, "build/out.bin", "src/gen/g.c", "readme",
                             "src/sub/gen/k.c", "build/.snapignore")
        assert (code, err) == (0, "")
        assert out == (".snapignore:2:build/\tbuild/out.bin\n"
                       "src/.snapignore:2:/gen/\tsrc/gen/g.c\n"
                       "config:1:readme\treadme\n"
                       "config:2:src/sub\tsrc/sub/gen/k.c\n"
                       ".snapignore:2:build/\tbuild/.snapignore\n")

    def part1(tmp_path):
        make(tmp_path, {".snapignore": "a\n", "sub/.snapignore": "x\n!//\n"})
        root = str(tmp_path)
        code, out, err = run("check-ignore", "--root", root, "a", "sub/f", "a")
        assert (code, out, err) == (2, ".snapignore:1:a\ta\n", "snapkit: sub/.snapignore:2: empty pattern\n")
        code, out, err = run("check-ignore", "--root", root, "../x")
        assert (code, out, err) == (2, "", "snapkit: '..' not allowed: '../x'\n")
        code, out, err = run("check-ignore", "--root", root)
        assert code == 2 and out == "" and err.startswith("snapkit: ")
        make(tmp_path, {".snapignore": "sub/\n"})
        assert run("check-ignore", "--root", root, "sub/f") == (0, ".snapignore:1:sub/\tsub/f\n", "")

    (tmp_path / 'p0').mkdir()
    part0(tmp_path / 'p0')
    (tmp_path / 'p1').mkdir()
    part1(tmp_path / 'p1')


# --- extended groups ---------------------------------------------------------

def test_at_group_alternatives():
    assert m("@(a|b).c", "a.c") and m("@(a|b).c", "b.c")
    assert not m("@(a|b).c", "ab.c") and not m("@(a|b).c", ".c")
    assert m("x@(ab|a)b", "xab") and m("x@(ab|a)b", "xabb") and not m("x@(ab|a)b", "x")


def test_question_group():
    assert m("x?(ab)y", "xy") and m("x?(ab)y", "xaby")
    assert not m("x?(ab)y", "xay") and not m("x?(ab)y", "xababy")


def test_star_and_plus_groups():
    assert m("x*(ab)", "x") and m("x*(ab)", "xabab") and not m("x*(ab)", "xa") and not m("x*(ab)", "xaba")
    assert m("x+(ab|c)", "xabcab") and m("x+(ab|c)", "xcc") and not m("x+(ab|c)", "x") and not m("x+(ab|c)", "xac")
    assert m("+(a|ab)b", "aab") and m("+(ab|a)", "aba") and m("+(ab|ba)a", "aba") and m("*(ab)ab", "ab")
    assert not m("+(ab|ba)", "aab")


def test_not_group_alone():
    assert m("!(*.c)", "a.h") and not m("!(*.c)", "a.c") and m("!(*.c)", "c")
    assert m("!(a|b)", "ab") and not m("!(a|b)", "a") and m("!(a)", "aa")


def test_not_group_with_neighbours():
    assert not m("a!(b)c", "abc")
    assert m("a!(b)c", "ac") and m("a!(b)c", "abbc") and m("a!(b)c", "axc")
    assert not m("!(a)b", "ab") and m("!(a)b", "b") and m("!(a)b", "aab")


def test_not_group_can_take_the_empty_piece():
    assert m("!(foo)*", "foo") and m("*!(x)", "x")
    assert not m("!(foo).txt", "foo.txt") and m("!(foo).txt", ".txt")
    assert not m("!(*)", "a") and not m("!(*)x", "x")


def test_empty_alternatives_and_empty_groups():
    assert m("a@(|b)c", "ac") and m("a@(|b)c", "abc")
    assert not m("a!()c", "ac") and m("a!()c", "abc")
    assert m("a@()b", "ab") and m("a?()b", "ab") and m("a+()b", "ab") and m("a*()b", "ab")
    assert not m("a+()b", "axb")


def test_nested_groups():
    assert m("+(a|@(b|c)d)", "abd") and m("+(a|@(b|c)d)", "cdcda") and not m("+(a|@(b|c)d)", "bc")
    assert not m("!(+(ab))", "abab") and m("!(+(ab))", "aba")
    assert not m("@(a|!(b))", "b") and m("@(a|!(b))", "c")


def test_groups_contain_any_glob():
    assert m("@(*.py|[0-9]?)", "x.py") and m("@(*.py|[0-9]?)", "1a") and not m("@(*.py|[0-9]?)", "1")
    assert m("+([[:digit:]])", "123") and not m("+([[:digit:]])", "12a")
    assert m(r"@(\*|?)", "*") and not m(r"@(\*|?)", "ab")


def test_escapes_and_ordinary_group_characters():
    assert m(r"@(a\|b)", "a|b") and not m(r"@(a\|b)", "a")
    assert m(r"@(a\))", "a)")
    assert glob_error(r"@(a|b\)") == "unclosed group in pattern " + repr(r"@(a|b\)")
    assert m("a|b", "a|b") and m("(a)", "(a)") and m("+a", "+a") and m("@", "@") and m("a)", "a)")
    assert m(r"\@(a)", "@(a)") and not m(r"\@(a)", "a")


def test_brackets_inside_groups():
    assert m("@([)|]x)", ")x") and m("@([)|]x)", "|x") and not m("@([)|]x)", "x")
    assert m("@(a[)", "a[")
    assert not m("@([!|])", "|") and m("@([!|])", "q")


def test_double_star_and_slashes_with_groups():
    assert m("@(**)", "abc") and m("@(**)/x", "a/x") and not m("@(**)/x", "a/b/x")
    assert glob_error("@(a/b)") == "unclosed group in pattern '@(a/b)'"
    assert m("**/@(x|y)", "a/b/y")


def test_group_errors_and_their_order():
    assert glob_error("@(a") == "unclosed group in pattern '@(a'"
    assert glob_error("!(a|b") == "unclosed group in pattern '!(a|b'"
    assert glob_error("@(@(a)") == "unclosed group in pattern '@(@(a)'"
    assert glob_error("@(a[z-a]") == "invalid range 'z'-'a' in pattern '@(a[z-a]'"
    assert glob_error("[z-a]@(") == "invalid range 'z'-'a' in pattern '[z-a]@('"
    assert glob_error("@(a/[z-a]") == "unclosed group in pattern '@(a/[z-a]'"
    assert glob_error("a\\/@(") == "trailing backslash in pattern " + repr("a\\/@(")
    assert glob_error("@(a[[:x:]])") == "unknown class 'x' in pattern '@(a[[:x:]])'"


def test_casefold_in_groups():
    assert m("@(README|*.MD)", "readme", True) and m("@(README|*.MD)", "x.md", True)
    assert not m("@(README|*.MD)", "readme")
    assert not m("!(a)", "A", True) and m("!(a)", "A")
    assert m("+([A-C])", "abc", True)


def test_groups_in_rules_files():
    got = rules("*.@(o|so)\n!(a)\n!!(*.c)\n@(!(a))\n", "f")
    assert [(r.negated, r.pattern) for r in got] == [
        (False, "*.@(o|so)"), (True, "(a)"), (True, "!(*.c)"), (False, "@(!(a))")]
    assert got[0].matches("lib/x.so", False) and not got[0].matches("lib/x.s", False)
    assert got[1].matches("(a)", False) and not got[1].matches("a", False)
    assert got[2].matches("x.h", False) and not got[2].matches("x.c", False)
    assert got[3].matches("b", False) and not got[3].matches("a", False)
    assert rule_error("ok\n@(a\n", "f") == "f:2: unclosed group in pattern '@(a'"


# --- brace expansion -----------------------------------------------------------

def test_brace_lists():
    assert expand("{a,b}{1,2}") == ["a1", "a2", "b1", "b2"]
    assert expand("a{b,c{d,e}}f") == ["abf", "acdf", "acef"]
    assert expand("x{,.bak}") == ["x", "x.bak"]
    assert expand("{a,b,a}") == ["a", "b"]
    assert expand("{a,b}{a,b}") == ["aa", "ab", "ba", "bb"]
    assert expand("{a,b{1,2}}{x,y}") == ["ax", "ay", "b1x", "b1y", "b2x", "b2y"]
    assert expand("plain") == ["plain"] and expand("{,}") == [""]


def test_brace_sequences():
    assert expand("{1..5}") == ["1", "2", "3", "4", "5"] and expand("{5..1}") == ["5", "4", "3", "2", "1"]
    assert expand("{01..10..3}") == ["01", "04", "07", "10"]
    assert expand("{-05..2}") == ["-05", "-04", "-03", "-02", "-01", "000", "001", "002"]
    assert expand("{1..10..-3}") == ["1", "4", "7", "10"] and expand("{10..1..3}") == ["10", "7", "4", "1"]
    assert expand("{a..e..2}") == ["a", "c", "e"] and expand("{E..A}") == ["E", "D", "C", "B", "A"]
    assert expand("{1..010}") == ["001", "002", "003", "004", "005", "006", "007", "008", "009", "010"]
    assert expand("{-2..2}") == ["-2", "-1", "0", "1", "2"] and expand("{0..3}") == ["0", "1", "2", "3"]
    assert expand("{-01..1}") == ["-01", "000", "001"]
    assert expand("{3..3}") == ["3"] and expand("{1..2..5}") == ["1"]
    assert expand("f{1..2}.{a..b}") == ["f1.a", "f1.b", "f2.a", "f2.b"]


def test_braces_that_stay_literal():
    for text in ("{a}", "{}", "{1..a}", "{a..Z}", "{+1..3}", "{1..3..0}", "{1...3}", "{a..b..c}", "{ab..c}",
                 "a}b{", "{a,{b}", "\\{a,b\\}", "{a,b\\}"):
        assert expand(text) == [text], text
    assert expand("{a{b,c}}") == ["{ab}", "{ac}"]
    assert expand("{a\\,b,c}") == ["a\\,b", "c"]
    assert expand("[{a,b}]") == ["[a]", "[b]"]
    assert expand("@({a,b}|c)") == ["@(a|c)", "@(b|c)"]


def test_brace_limit():
    assert len(expand("{a,b}" * 8)) == 256 and len(expand("{1..256}")) == 256
    for text in ("{a,b}" * 9, "{a,a}" * 9, "{1..300}"):
        with pytest.raises(errors.BraceError) as exc:
            expand(text)
        assert str(exc.value) == "brace expansion exceeds 256 patterns"
        assert isinstance(exc.value, errors.SnapError)


def test_braces_in_rules_files():
    got = rules("{a,b}{1,2}/\n!{src/gen,build}\n# {x,y}\n{x,y}\\ \n{a,b\n", "f")
    assert [(r.line, r.text, r.negated, r.dir_only, r.anchored, r.pattern) for r in got] == [
        (1, "{a,b}{1,2}/", False, True, False, "a1"), (1, "{a,b}{1,2}/", False, True, False, "a2"),
        (1, "{a,b}{1,2}/", False, True, False, "b1"), (1, "{a,b}{1,2}/", False, True, False, "b2"),
        (2, "!{src/gen,build}", True, False, True, "src/gen"), (2, "!{src/gen,build}", True, False, False, "build"),
        (4, "{x,y}\\ ", False, False, False, "x\\ "), (4, "{x,y}\\ ", False, False, False, "y\\ "),
        (5, "{a,b", False, False, False, "{a,b")]
    assert rule_error("ok\n{a,}/\n", "f") == "f:2: empty pattern"
    assert rule_error("!{,x}\n", "f") == "f:1: empty pattern"
    assert rule_error("{ok,[z-a],[[:x:]]}\n", "f") == "f:1: invalid range 'z'-'a' in pattern '[z-a]'"
    assert rule_error("#\n" + "{a,b}" * 9 + "\n", "f") == "f:2: brace expansion exceeds 256 patterns"


def test_groups_and_braces_end_to_end(tmp_path):
    make(tmp_path, {".snapignore": "*.@(log|tmp)\n{build,dist}/\n!keep.{log,tmp}\nv{1..3}/\ndata/!(*.csv)\n",
                    "a.log": "1", "a.txt": "2", "keep.log": "3", "keep.tmp": "4", "x.tmp": "5",
                    "build/o": "6", "dist/o": "7", "distx/o": "8", "v1/f": "9", "v2/f": "a", "v4/f": "b",
                    "v01/f": "c", "data/a.csv": "d", "data/b.json": "e", "data/c.csv.x": "f"})
    code, out, err = run("snapshot", "--root", str(tmp_path))
    assert (code, err) == (0, "")
    assert listed(out) == [".snapignore", "a.txt", "data/a.csv", "distx/o", "keep.log", "keep.tmp", "v01/f", "v4/f"]
    assert run("check-ignore", "--root", str(tmp_path), "keep.tmp", "v2/f", "data/b.json", "dist/o/x") == (
        0, ".snapignore:3:!keep.{log,tmp}\tkeep.tmp\n.snapignore:4:v{1..3}/\tv2/f\n"
           ".snapignore:5:data/!(*.csv)\tdata/b.json\n.snapignore:2:{build,dist}/\tdist/o/x\n", "")


def test_match_command():
    assert run("match", "**/*.@(c|h)", "a.c", "b.py", "./x//y.h") == (0, "yes\ta.c\nno\tb.py\nyes\tx/y.h\n", "")
    assert run("match", "{src,lib}/*.py", "lib/a.py") == (0, "yes\tlib/a.py\n", "")
    assert run("match", "{src,lib}/*.py", "a.py") == (1, "no\ta.py\n", "")
    assert run("match", "--ignore-case", "*.TXT", "a.txt") == (0, "yes\ta.txt\n", "")
    assert run("match", "*.TXT", "a.txt") == (1, "no\ta.txt\n", "")
    assert run("match", "{ok,[z-a],@(}", "x") == (2, "", "snapkit: invalid range 'z'-'a' in pattern '[z-a]'\n")
    assert run("match", "{a,b}" * 9, "x") == (2, "", "snapkit: brace expansion exceeds 256 patterns\n")
    assert run("match", "a", "ok", "../x") == (2, "no\tok\n", "snapkit: '..' not allowed: '../x'\n")
    code, out, err = run("match", "a")
    assert code == 2 and out == "" and err.startswith("snapkit: ")
