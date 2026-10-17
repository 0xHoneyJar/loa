import io

import pytest

from permit import cli
from permit.engine import Evaluator
from permit.errors import DirectoryError, PathError, PermitError, RuleError
from permit.paths import normalize, segments
from permit.principals import Directory, parse_directory
from permit.rules import Rule, parse_rule, parse_rules

USERS = "alice: staff, admins\nbob: staff\ncarol:\n"
POLICY = """# who may do what
allow alice read /docs/report.txt
allow @staff write /shared/notes
allow @admins delete /docs/report.txt
"""


def evaluator(policy=POLICY):
    return Evaluator(parse_directory(USERS), parse_rules(policy, "policy"))


def test_normalize_and_segments():
    assert normalize("/docs//a/") == "/docs/a"
    assert normalize("/") == "/"
    assert segments("/docs/a") == ["docs", "a"] and segments("/") == []


@pytest.mark.parametrize("bad", ["docs/a", "", "/a/../b", "/a/./b", None])
def test_bad_paths(bad):
    with pytest.raises(PathError) as exc:
        normalize(bad)
    assert str(exc.value) == f"bad path: {bad!r}"


def test_parse_directory():
    d = parse_directory("# people\nalice: staff, admins\nbob: staff\ncarol:\n")
    assert d.groups_of("alice") == {"staff", "admins"} and d.groups_of("carol") == frozenset()
    assert d.groups_of("nobody") == frozenset() and d.users() == ["alice", "bob", "carol"]


@pytest.mark.parametrize("text,message", [
    ("alice staff\n", "users:1: expected 'user: group, group'"),
    ("alice: staff\nal ice: x\n", "users:2: expected 'user: group, group'"),
    ("alice: a\nalice: b\n", "users:2: alice listed twice"),
])
def test_directory_errors(text, message):
    with pytest.raises(DirectoryError) as exc:
        parse_directory(text)
    assert str(exc.value) == message


def test_parse_rules_skips_blanks_and_comments():
    rules = parse_rules("\n# c\nallow alice read /a  # trailing\n\nallow @staff write /b\n", "policy")
    assert rules == [
        Rule("allow", "alice", "read", "/a", "policy", 3),
        Rule("allow", "@staff", "write", "/b", "policy", 5),
    ]


@pytest.mark.parametrize("text,message", [
    ("allow alice read", "policy:7: expected 4 fields, got 3"),
    ("allow alice read /a extra", "policy:7: expected 4 fields, got 5"),
    ("permit alice read /a", "policy:7: unknown effect 'permit'"),
    ("allow alice read docs", "policy:7: pattern must start with /: 'docs'"),
])
def test_rule_errors(text, message):
    with pytest.raises(RuleError) as exc:
        parse_rule(text, "policy", 7)
    assert str(exc.value) == message
    assert issubclass(RuleError, PermitError)


def test_exact_allow_rules():
    ev = evaluator()
    assert ev.check("alice", "read", "/docs/report.txt")
    assert ev.check("alice", "read", "/docs//report.txt/")
    assert not ev.check("bob", "read", "/docs/report.txt")
    assert not ev.check("alice", "write", "/docs/report.txt")


def test_group_rules():
    ev = evaluator()
    assert ev.check("bob", "write", "/shared/notes") and ev.check("alice", "write", "/shared/notes")
    assert not ev.check("carol", "write", "/shared/notes")
    assert ev.check("alice", "delete", "/docs/report.txt") and not ev.check("bob", "delete", "/docs/report.txt")


def test_no_rules_means_no_access():
    ev = Evaluator(Directory(), [])
    assert not ev.check("alice", "read", "/")


def test_request_path_is_checked():
    with pytest.raises(PathError):
        evaluator().check("alice", "read", "docs/report.txt")


def run_cli(argv):
    out, err = io.StringIO(), io.StringIO()
    return cli.main(argv, stdout=out, stderr=err), out.getvalue(), err.getvalue()


@pytest.fixture
def files(tmp_path):
    users, policy = tmp_path / "users", tmp_path / "policy"
    users.write_text(USERS)
    policy.write_text(POLICY)
    return ["--policy", str(policy), "--users", str(users)]


def test_cli_check(files):
    assert run_cli(["check", *files, "alice", "read", "/docs/report.txt"]) == (0, "allow\n", "")
    assert run_cli(["check", *files, "bob", "read", "/docs/report.txt"]) == (0, "deny\n", "")


def test_cli_errors(files, tmp_path):
    code, out, err = run_cli(["check", "alice", "read", "/a"])
    assert code == 2 and out == "" and err.startswith("usage: permit check")
    bad = tmp_path / "bad"
    bad.write_text("allow alice read /a\npermit bob read /b\n")
    assert run_cli(["check", "--policy", str(bad), files[2], files[3], "alice", "read", "/a"]) == (
        2, "", "permit: policy:2: unknown effect 'permit'\n")
    assert run_cli(["check", *files, "alice", "read", "a"]) == (2, "", "permit: bad path: 'a'\n")
