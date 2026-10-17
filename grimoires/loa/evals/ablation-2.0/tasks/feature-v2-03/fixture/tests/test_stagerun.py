import io
import json

import pytest

from stagerun import cli, steps
from stagerun.errors import PipelineError, SpecError
from stagerun.pipeline import Pipeline
from stagerun.spec import parse_spec
from stagerun.store import read_json, write_json


def test_builtin_steps():
    assert steps.strip([" a ", "b"]) == ["a", "b"]
    assert steps.lower(["A", "b"]) == ["a", "b"]
    assert steps.nonempty(["", "x", ""]) == ["x"]
    assert steps.dedupe(["b", "a", "b", "c", "a"]) == ["b", "a", "c"]
    assert steps.sort(["b", "a"]) == ["a", "b"]
    assert steps.count(["b", "a", "b"]) == {"a": 1, "b": 2}


@pytest.mark.parametrize("bad", [None, "abc", [1], {"a": 1}])
def test_steps_want_a_list_of_strings(bad):
    with pytest.raises(PipelineError, match="^dedupe: expected a list of strings$"):
        steps.dedupe(bad)


def test_parse_spec():
    pairs = parse_spec("# words\nstrip\n\nlower  # case\ncount\n")
    assert [name for name, _ in pairs] == ["strip", "lower", "count"]
    assert pairs[2][1] is steps.count


@pytest.mark.parametrize("text,message", [
    ("strip\nshout\n", "line 2: unknown step 'shout'"),
    ("# nothing\n\n", "a spec needs at least one step"),
])
def test_spec_errors(text, message):
    with pytest.raises(SpecError) as exc:
        parse_spec(text)
    assert str(exc.value) == message


def test_pipeline_runs_steps_in_order():
    seen = []

    def tag(label):
        def step(data):
            seen.append(label)
            return data + [label]
        return step

    p = Pipeline([("a", tag("a")), ("b", tag("b"))])
    assert p.run([]) == ["a", "b"] and seen == ["a", "b"] and p.names() == ["a", "b"]
    assert Pipeline.from_spec("strip\ndedupe\nsort").run([" b", "a", "b "]) == ["a", "b"]


@pytest.mark.parametrize("steps_arg,message", [
    ([], "a pipeline needs at least one step"),
    ([("a", len), ("", len)], "bad step 2: expected a (name, function) pair"),
    ([("a", "len")], "bad step 1: expected a (name, function) pair"),
])
def test_pipeline_checks_its_steps(steps_arg, message):
    with pytest.raises(PipelineError) as exc:
        Pipeline(steps_arg)
    assert str(exc.value) == message


def test_step_errors_propagate_unchanged():
    def boom(data):
        raise KeyError("x")

    with pytest.raises(KeyError):
        Pipeline([("ok", list), ("boom", boom)]).run([])


def test_write_json_is_atomic_and_readable(tmp_path):
    path = tmp_path / "out.json"
    write_json(str(path), {"b": [1], "a": "é"})
    assert read_json(str(path)) == {"a": "é", "b": [1]}
    assert path.read_text(encoding="utf-8").startswith('{\n  "a": "é"')
    assert sorted(p.name for p in tmp_path.iterdir()) == ["out.json"]


def run_cli(argv):
    out, err = io.StringIO(), io.StringIO()
    return cli.main(argv, stdout=out, stderr=err), out.getvalue(), err.getvalue()


@pytest.fixture
def files(tmp_path):
    spec = tmp_path / "words.spec"
    spec.write_text("strip\nlower\nnonempty\ncount\n")
    data = tmp_path / "in.json"
    data.write_text(json.dumps([" Apple", "apple ", "", "Pear"]))
    return spec, data, tmp_path / "out.json"


def test_cli_run(files):
    spec, data, out = files
    assert run_cli(["run", str(spec), str(data), str(out)]) == (0, "", "")
    assert json.loads(out.read_text()) == {"apple": 2, "pear": 1}


def test_cli_errors(files, tmp_path):
    spec, data, out = files
    assert run_cli(["run", str(spec), str(data)])[0] == 2
    bad = tmp_path / "bad.json"
    bad.write_text("[1,")
    assert run_cli(["run", str(spec), str(bad), str(out)]) == (1, "", f"stagerun: {bad}: not JSON\n")
    nums = tmp_path / "nums.json"
    nums.write_text("[1, 2]")
    assert run_cli(["run", str(spec), str(nums), str(out)]) == (1, "", "stagerun: strip: expected a list of strings\n")
    assert run_cli(["run", str(tmp_path / "none.spec"), str(data), str(out)]) == (1, "", f"stagerun: {tmp_path / 'none.spec'}: cannot read\n")
    assert not out.exists()
