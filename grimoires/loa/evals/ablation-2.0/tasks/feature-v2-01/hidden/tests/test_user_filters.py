import io
import json

import pytest

from textpipe.cli import main


def run_cli(argv, text=""):
    out, err = io.StringIO(), io.StringIO()
    code = main(argv, stdin=io.StringIO(text), stdout=out, stderr=err)
    return code, out.getvalue(), err.getvalue()


def config(tmp_path, data):
    path = tmp_path / "textpipe.json"
    path.write_text(data if isinstance(data, str) else json.dumps(data), encoding="utf-8")
    return str(path)


def usage_error(result, message):
    assert result == (2, "", f"textpipe: {message}\n")


def test_config_and_command_line_definitions_apply_in_step_order(tmp_path):
    cfg = config(tmp_path, {"filters": {"shout": ["strip", "upper"]}})
    assert run_cli(["--config", cfg, "--apply", "shout"], "  hi there \n") == (0, "HI THERE\n", "")
    assert run_cli(["--define", "tidy=squeeze,strip,rev", "--apply", "tidy,upper"], " a  b \n") == (0, "B A\n", "")
    # the config apply list may name a config or command-line definition
    cfg2 = config(tmp_path, {"filters": {"shout": ["upper"]}, "apply": ["shout", "loud"]})
    assert run_cli(["--config", cfg2, "--define", "loud=rev"], "ab\n") == (0, "BA\n", "")


def test_command_line_replaces_config_which_replaces_builtin(tmp_path):
    cfg = config(tmp_path, {"filters": {"shout": ["upper"], "lower": ["rev"]}})
    assert run_cli(["--config", cfg, "--define", "shout=rev", "--apply", "shout"], "ab\n") == (0, "ba\n", "")
    assert run_cli(["--config", cfg, "--apply", "lower"], "Ab\n") == (0, "bA\n", "")
    assert run_cli(["--config", cfg, "--define", "lower=upper", "--apply", "lower"], "ab\n") == (0, "AB\n", "")


def test_steps_always_mean_the_builtin_filter(tmp_path):
    cfg = config(tmp_path, {"filters": {"upper": ["lower"], "shout": ["strip", "upper"]}, "disable": ["strip"]})
    assert run_cli(["--config", cfg, "--apply", "shout"], " ab \n") == (0, "AB\n", "")
    assert run_cli(["--config", cfg, "--apply", "upper"], "AB\n") == (0, "ab\n", "")
    usage_error(run_cli(["--define", "a=strip", "--define", "b=a"]), "unknown step a in b")


def test_removal_deletes_the_name_and_brings_nothing_back(tmp_path):
    cfg = config(tmp_path, {"filters": {"upper": ["rev"], "shout": ["upper"]}})
    usage_error(run_cli(["--config", cfg, "--undefine", "upper", "--apply", "upper"], "x\n"), "unknown filter: upper")
    usage_error(run_cli(["--config", cfg, "--undefine", "shout", "--apply", "shout"], "x\n"), "unknown filter: shout")
    cfg2 = config(tmp_path, {"disable": ["rev"]})
    usage_error(run_cli(["--config", cfg2, "--apply", "rev"], "x\n"), "unknown filter: rev")


def test_removals_follow_definitions_within_a_source(tmp_path):
    usage_error(run_cli(["--undefine", "tmp", "--define", "tmp=upper", "--apply", "tmp"], "x\n"), "unknown filter: tmp")
    cfg = config(tmp_path, {"disable": ["mine"], "filters": {"mine": ["upper"]}})
    usage_error(run_cli(["--config", cfg, "--apply", "mine"], "x\n"), "unknown filter: mine")
    # the command line comes after the config file
    cfg2 = config(tmp_path, {"disable": ["upper"]})
    assert run_cli(["--config", cfg2, "--define", "upper=rev", "--apply", "upper"], "ab\n") == (0, "ba\n", "")


def test_unknown_names_in_removals_and_in_the_config_apply_list(tmp_path):
    usage_error(run_cli(["--undefine", "nope"]), "unknown filter: nope")
    cfg = config(tmp_path, {"disable": ["nope"]})
    usage_error(run_cli(["--config", cfg]), "config: unknown filter: nope")
    # a config removal sees only the built-ins and the config, not the command line
    usage_error(run_cli(["--config", cfg, "--define", "nope=upper"]), "config: unknown filter: nope")
    # the config apply list is checked against the complete registry, even when --apply is given
    cfg2 = config(tmp_path, {"filters": {"shout": ["upper"]}, "apply": ["shout"]})
    usage_error(run_cli(["--config", cfg2, "--undefine", "shout", "--apply", "rev"], "x\n"), "config: unknown filter: shout")


def test_listing_is_sorted_with_sources(tmp_path):
    cfg = config(tmp_path, {"filters": {"shout": ["strip", "upper"], "lower": ["rev"]}, "disable": ["squeeze"]})
    code, out, err = run_cli(["--config", cfg, "--define", "a-very-long-name=rev,rev", "--undefine", "strip", "--list"])
    assert (code, err) == (0, "")
    assert out == (
        "a-very-long-name  rev | rev [command line]\n"
        "lower             rev [config]\n"
        "rev               reverse the characters of the line\n"
        "shout             strip | upper [config]\n"
        "upper             uppercase the line\n"
    )


def test_listing_of_an_empty_registry_prints_nothing():
    argv = ["--list"]
    for name in ("lower", "rev", "squeeze", "strip", "upper"):
        argv += ["--undefine", name]
    assert run_cli(argv) == (0, "", "")


@pytest.mark.parametrize("name", ["Shout", "9lives", "a.b", "x" * 33])
def test_invalid_names(tmp_path, name):
    usage_error(run_cli(["--define", f"{name}=upper"]), f"invalid filter name: {name}")
    cfg = config(tmp_path, {"filters": {name: ["upper"]}})
    usage_error(run_cli(["--config", cfg]), f"config: invalid filter name: {name}")


def test_longest_valid_name_and_boundary_characters():
    name = "z" + "9_-" * 10 + "q"
    assert len(name) == 32
    assert run_cli(["--define", f"{name}=upper", "--apply", name], "a\n") == (0, "A\n", "")


def test_definition_shapes(tmp_path):
    for value in ["shout", "shout=", "shout=strip,,upper", "shout=strip,", "=upper", "shout=strip, upper", "a=b=c"]:
        usage_error(run_cli(["--define", value]), f"invalid --define value: {value}")
    for steps in [[], "upper", ["upper", 3], None]:
        cfg = config(tmp_path, {"filters": {"shout": steps}})
        usage_error(run_cli(["--config", cfg]), "config: invalid definition of shout: steps must be a non-empty list of names")
    cfg = config(tmp_path, {"disable": "upper"})
    usage_error(run_cli(["--config", cfg]), "config: disable must be a list of filter names")


def test_unknown_steps(tmp_path):
    usage_error(run_cli(["--define", "x=strip,nope"]), "unknown step nope in x")
    cfg = config(tmp_path, {"filters": {"x": ["nope"]}})
    usage_error(run_cli(["--config", cfg]), "config: unknown step nope in x")


def test_duplicate_definitions_within_one_source(tmp_path):
    usage_error(run_cli(["--define", "a=strip", "--define", "a=upper"]), "duplicate definition of a on the command line")
    cfg = config(tmp_path, '{"filters": {"a": ["strip"], "a": ["upper"]}}')
    usage_error(run_cli(["--config", cfg]), "config: duplicate definition of a")
    # the same name in two sources is a replacement, not a duplicate
    cfg2 = config(tmp_path, {"filters": {"a": ["strip"]}})
    assert run_cli(["--config", cfg2, "--define", "a=upper", "--apply", "a"], " b \n") == (0, " B \n", "")
