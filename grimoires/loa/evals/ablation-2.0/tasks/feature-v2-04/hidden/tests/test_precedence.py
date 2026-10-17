import io

import pytest

from permit import cli
from permit.engine import Evaluator
from permit.errors import PathError, RuleError
from permit.principals import parse_directory
from permit.rules import parse_rule, parse_rules

USERS = "alice: staff, admins\nbob: staff\ncarol: interns\n"


def ev(policy, overrides=""):
    return Evaluator(parse_directory(USERS), parse_rules(policy, "policy"), parse_rules(overrides, "overrides"))


def test_deny_by_default_and_for_unknown_users():
    e = ev("allow @staff read /docs/**\n")
    assert not e.check("carol", "read", "/docs/a")
    assert not e.check("zed", "read", "/docs/a")
    assert str(e.explain("zed", "read", "/docs/a")) == "deny by default"
    assert e.explain("zed", "read", "/docs/a").rule is None
    assert ev("allow * read /**\n").check("zed", "read", "/docs/a")


def test_single_and_double_star_segments():
    e = ev("allow * read /docs/*\nallow * write /src/**\n")
    assert e.check("bob", "read", "/docs/a")
    assert not e.check("bob", "read", "/docs") and not e.check("bob", "read", "/docs/a/b")
    assert e.check("bob", "write", "/src") and e.check("bob", "write", "/src/a/b/c")
    assert not e.check("bob", "write", "/srcx") and not e.check("bob", "write", "/")
    assert ev("allow * * /**\n").check("bob", "anything", "/")


def test_explicit_deny_beats_allow_of_the_same_specificity():
    e = ev("allow @staff read /docs/*\ndeny alice read /docs/*\n")
    assert not e.check("alice", "read", "/docs/a")
    assert e.check("bob", "read", "/docs/a")
    assert str(e.explain("alice", "read", "/docs/a")) == "deny by policy:2: deny alice read /docs/*"


def test_a_more_specific_allow_beats_a_broader_deny():
    e = ev("deny * * /docs/**\nallow alice read /docs/public/a.txt\n")
    assert e.check("alice", "read", "/docs/public/a.txt")
    assert not e.check("alice", "read", "/docs/public/b.txt")
    assert not e.check("bob", "read", "/docs/public/a.txt")


def test_specificity_order():
    lit = ev("deny * read /a/*/*\nallow * read /a/b/**\n")
    assert lit.check("bob", "read", "/a/b/c")
    nostar = ev("deny * read /a/b/**\nallow * read /a/b/*\n")
    assert nostar.check("bob", "read", "/a/b/c") and not nostar.check("bob", "read", "/a/b/c/d")
    fewer = ev("deny @staff read /a/*/**\nallow alice read /a/**\n")
    assert fewer.check("alice", "read", "/a/b/c") and fewer.check("alice", "read", "/a")
    assert not fewer.check("bob", "read", "/a/b")


def test_principal_and_action_wildcards_do_not_change_specificity():
    e = ev("allow alice read /docs/*\ndeny * * /docs/*\n")
    assert not e.check("alice", "read", "/docs/a")
    e2 = ev("deny @staff * /docs/a\nallow alice read /docs/*\n")
    assert not e2.check("alice", "read", "/docs/a") and e2.check("alice", "read", "/docs/b")


def test_overrides_beat_the_policy_whatever_their_specificity():
    e = ev("allow alice read /docs/a\n", "deny * * /**\n")
    assert not e.check("alice", "read", "/docs/a")
    assert str(e.explain("alice", "read", "/docs/a")) == "deny by overrides:1: deny * * /**"
    e2 = ev("deny * * /docs/**\n", "# temporary\nallow bob read /docs/a/*\n")
    assert e2.check("bob", "read", "/docs/a/x") and not e2.check("bob", "read", "/docs/a")
    assert str(e2.explain("bob", "read", "/docs/a/x")) == "allow by overrides:2: allow bob read /docs/a/*"
    assert str(e2.explain("bob", "read", "/docs/a")) == "deny by policy:1: deny * * /docs/**"


def test_overrides_only_count_when_one_matches():
    e = ev("allow @staff read /docs/**\n", "deny bob read /docs/secret\ndeny carol * /**\n")
    assert e.check("alice", "read", "/docs/secret") and not e.check("bob", "read", "/docs/secret")
    assert e.check("bob", "read", "/docs/other")
    assert Evaluator(parse_directory(USERS), parse_rules("allow * * /**\n", "policy")).check("carol", "x", "/y")


def test_paths_and_patterns_are_normalised():
    e = ev("allow alice read /docs//a/\nallow bob read /src//**\n")
    assert e.check("alice", "read", "/docs/a/") and e.check("alice", "read", "//docs/a")
    assert e.check("bob", "read", "/src") and e.check("bob", "read", "/src//x/")
    assert str(e.explain("alice", "read", "/docs/a")) == "allow by policy:1: allow alice read /docs//a/"
    with pytest.raises(PathError):
        e.check("alice", "read", "/docs/../a")


def test_the_deciding_rule_is_the_first_winner_in_file_order():
    e = ev("allow * read /x/*\nallow @staff read /*/y\ndeny carol read /x/y\nallow bob read /x/y\nallow alice * /x/y\n")
    d = e.explain("alice", "read", "/x/y")
    assert d.allowed is True and d.rule.line == 5 and d.rule.source == "policy"
    assert str(e.explain("bob", "read", "/x/y")) == "allow by policy:4: allow bob read /x/y"
    assert str(e.explain("bob", "read", "/x/z")) == "allow by policy:1: allow * read /x/*"
    assert str(e.explain("bob", "read", "/w/y")) == "allow by policy:2: allow @staff read /*/y"
    assert str(e.explain("carol", "read", "/x/y")) == "deny by policy:3: deny carol read /x/y"
    assert e.check("alice", "read", "/x/y") is True and e.check("carol", "read", "/x/y") is False
    tie = ev("allow @staff read /x/*\nallow alice read /*/q\nallow alice read /x/*\n")
    assert str(tie.explain("alice", "read", "/x/q")) == "allow by policy:1: allow @staff read /x/*"
    deny_tie = ev("allow alice read /x/*\ndeny @staff read /*/q\ndeny alice read /x/*\n")
    assert str(deny_tie.explain("alice", "read", "/x/q")) == "deny by policy:2: deny @staff read /*/q"


def test_malformed_rules():
    cases = [
        ("deny alice read", "expected 4 fields, got 3"),
        ("block alice read /a", "unknown effect 'block'"),
        ("allow @ read /a", "bad principal '@'"),
        ("allow @* read /a", "bad principal '@*'"),
        ("allow al*ce read /a", "bad principal 'al*ce'"),
        ("allow alice re*d /a", "bad action 're*d'"),
        ("allow alice ** /a", "bad action '**'"),
        ("allow alice read docs/*", "pattern must start with /: 'docs/*'"),
        ("allow alice read /a/../b", "bad pattern: '/a/../b'"),
        ("allow alice read /docs/a*", "wildcard must be a whole segment: '/docs/a*'"),
        ("allow alice read /docs/***", "wildcard must be a whole segment: '/docs/***'"),
        ("allow alice read /a/**/b", "'**' must be the last segment: '/a/**/b'"),
        ("permit al*ce read docs", "unknown effect 'permit'"),
        ("deny @g* x/y /a/*b", "bad principal '@g*'"),
    ]
    for text, reason in cases:
        with pytest.raises(RuleError) as exc:
            parse_rule(text, "overrides", 4)
        assert str(exc.value) == f"overrides:4: {reason}", text
    assert parse_rule("deny bob.smith-2 x_y.z /a/*/**", "policy", 1).effect == "deny"


def run_cli(argv):
    out, err = io.StringIO(), io.StringIO()
    return cli.main(argv, stdout=out, stderr=err), out.getvalue(), err.getvalue()


def test_cli_overrides_and_explain(tmp_path):
    users, policy, overrides = tmp_path / "users", tmp_path / "policy", tmp_path / "overrides"
    users.write_text(USERS)
    policy.write_text("allow @staff read /docs/**\ndeny * * /docs/secret/**\n")
    overrides.write_text("allow alice read /docs/secret/plan\n")
    base = ["check", "--policy", str(policy), "--users", str(users)]
    assert run_cli(base + ["bob", "read", "/docs/secret/plan"]) == (0, "deny\n", "")
    assert run_cli(base + ["--explain", "bob", "read", "/docs/a"]) == (0, "allow by policy:1: allow @staff read /docs/**\n", "")
    with_overrides = base + ["--overrides", str(overrides)]
    assert run_cli(with_overrides + ["alice", "read", "/docs/secret/plan"]) == (0, "allow\n", "")
    assert run_cli(with_overrides + ["--explain", "alice", "read", "/docs/secret/plan"]) == (
        0, "allow by overrides:1: allow alice read /docs/secret/plan\n", "")
    assert run_cli(with_overrides + ["--explain", "carol", "read", "/docs/a"]) == (0, "deny by default\n", "")


def test_cli_reports_a_malformed_override(tmp_path):
    users, policy, overrides = tmp_path / "users", tmp_path / "policy", tmp_path / "overrides"
    users.write_text(USERS)
    policy.write_text("allow * * /**\n")
    overrides.write_text("\ndeny bob read /a/**/b\n")
    argv = ["check", "--policy", str(policy), "--users", str(users), "--overrides", str(overrides), "bob", "read", "/a"]
    assert run_cli(argv) == (2, "", "permit: overrides:2: '**' must be the last segment: '/a/**/b'\n")
