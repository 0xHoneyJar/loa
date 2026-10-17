import hashlib
import io
import json

import pytest

from stagerun import cli
from stagerun.pipeline import Pipeline


def digest(value):
    text = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class Counter:
    """Steps that count their calls; ``fail`` makes the named step raise once."""

    def __init__(self):
        self.calls = []
        self.fail = set()

    def step(self, name, fn):
        def run(data):
            self.calls.append(name)
            if name in self.fail:
                self.fail.discard(name)
                raise RuntimeError(f"{name} failed")
            return fn(data)
        return (name, run)


def words(counter):
    return Pipeline([
        counter.step("lower", lambda d: [s.lower() for s in d]),
        counter.step("dedupe", lambda d: list(dict.fromkeys(d))),
        counter.step("count", lambda d: {s: len(s) for s in d}),
    ])


def entries(path):
    return json.loads(path.read_text(encoding="utf-8"))


def test_checkpoint_format_after_a_full_run(tmp_path):
    ck = tmp_path / "run.ckpt"
    c = Counter()
    p = words(c)
    assert p.run(["B", "a", "b"], checkpoint=ck) == {"b": 1, "a": 1}
    assert entries(ck) == {"version": 1, "steps": [
        {"name": "lower", "input": digest(["B", "a", "b"]), "output": ["b", "a", "b"]},
        {"name": "dedupe", "input": digest(["b", "a", "b"]), "output": ["b", "a"]},
        {"name": "count", "input": digest(["b", "a"]), "output": {"b": 1, "a": 1}},
    ]}
    assert p.last_run == [("lower", "ran"), ("dedupe", "ran"), ("count", "ran")]
    assert sorted(f.name for f in tmp_path.iterdir()) == ["run.ckpt"]


def test_resume_reuses_every_completed_step(tmp_path):
    ck = tmp_path / "run.ckpt"
    c = Counter()
    p = words(c)
    p.run(["B", "a"], checkpoint=str(ck))
    before = ck.read_text(encoding="utf-8")
    c.calls.clear()
    assert p.run(["B", "a"], checkpoint=str(ck), resume=True) == {"b": 1, "a": 1}
    assert c.calls == []
    assert p.last_run == [("lower", "reused"), ("dedupe", "reused"), ("count", "reused")]
    assert entries(ck) == json.loads(before)


def test_a_failed_step_restarts_from_its_recorded_input(tmp_path):
    ck = tmp_path / "run.ckpt"
    c = Counter()
    p = words(c)
    c.fail.add("dedupe")
    with pytest.raises(RuntimeError, match="^dedupe failed$"):
        p.run(["X", "x", "y"], checkpoint=ck)
    assert [e["name"] for e in entries(ck)["steps"]] == ["lower"]
    c.calls.clear()
    assert p.run(["X", "x", "y"], checkpoint=ck, resume=True) == {"x": 1, "y": 1}
    assert c.calls == ["dedupe", "count"]
    assert p.last_run == [("lower", "reused"), ("dedupe", "ran"), ("count", "ran")]
    assert [e["name"] for e in entries(ck)["steps"]] == ["lower", "dedupe", "count"]


def test_once_a_step_runs_every_later_step_runs(tmp_path):
    ck = tmp_path / "run.ckpt"
    c = Counter()
    p = words(c)
    p.run(["a", "b"], checkpoint=ck)
    c.calls.clear()
    assert p.run(["A", "B"], checkpoint=ck, resume=True) == {"a": 1, "b": 1}
    assert c.calls == ["lower", "dedupe", "count"]
    assert entries(ck)["steps"][0]["input"] == digest(["A", "B"])


def test_an_edited_middle_output_invalidates_the_steps_after_it(tmp_path):
    ck = tmp_path / "run.ckpt"
    c = Counter()
    p = words(c)
    p.run(["a", "b"], checkpoint=ck)
    doc = entries(ck)
    doc["steps"][1]["output"] = ["zz"]
    ck.write_text(json.dumps(doc), encoding="utf-8")
    c.calls.clear()
    assert p.run(["a", "b"], checkpoint=ck, resume=True) == {"zz": 2}
    assert c.calls == ["count"]
    assert p.last_run == [("lower", "reused"), ("dedupe", "reused"), ("count", "ran")]
    assert entries(ck)["steps"][2] == {"name": "count", "input": digest(["zz"]), "output": {"zz": 2}}


def test_a_run_without_resume_deletes_the_old_checkpoint_first(tmp_path):
    ck = tmp_path / "run.ckpt"
    c = Counter()
    p = words(c)
    p.run(["a"], checkpoint=ck)
    c.fail.add("lower")
    with pytest.raises(RuntimeError):
        p.run(["a"], checkpoint=ck)
    assert not ck.exists()
    c.calls.clear()
    p.run(["a"], checkpoint=ck, resume=True)
    assert c.calls == ["lower", "dedupe", "count"]


def test_resume_needs_a_checkpoint_and_tolerates_a_missing_file(tmp_path):
    c = Counter()
    p = words(c)
    with pytest.raises(ValueError, match="^resume needs a checkpoint$"):
        p.run(["a"], resume=True)
    assert c.calls == []
    assert p.run(["a"]) == {"a": 1} and p.last_run == [("lower", "ran"), ("dedupe", "ran"), ("count", "ran")]
    c.calls.clear()
    assert p.run(["a"], checkpoint=tmp_path / "new.ckpt", resume=True) == {"a": 1}
    assert c.calls == ["lower", "dedupe", "count"]


def test_a_checkpoint_from_another_pipeline_is_refused_before_any_step(tmp_path):
    from stagerun.errors import CheckpointError, PipelineError

    assert issubclass(CheckpointError, PipelineError)
    ck = tmp_path / "run.ckpt"
    c = Counter()
    words(c).run(["a"], checkpoint=ck)
    c.calls.clear()
    renamed = Pipeline([c.step("lower", str.upper), c.step("unique", list), c.step("count", len)])
    with pytest.raises(CheckpointError) as exc:
        renamed.run(["a"], checkpoint=ck, resume=True)
    assert str(exc.value) == "checkpoint step 2 is 'dedupe', pipeline step 2 is 'unique'"
    shorter = Pipeline([c.step("lower", str.upper), c.step("dedupe", list)])
    with pytest.raises(CheckpointError) as exc:
        shorter.run(["a"], checkpoint=ck, resume=True)
    assert str(exc.value) == "checkpoint has 3 steps, pipeline has 2"
    assert c.calls == []


def test_corrupt_checkpoints(tmp_path):
    from stagerun.errors import CheckpointError

    good = {"name": "lower", "input": digest(["a"]), "output": ["a"]}
    cases = [
        (b"{not json", "corrupt checkpoint: not JSON"),
        (b"\xff\xfe{}", "corrupt checkpoint: not JSON"),
        (b"[]", "corrupt checkpoint: not an object"),
        (b'{"steps": []}', "corrupt checkpoint: unsupported version None"),
        (b'{"version": "1", "steps": []}', "corrupt checkpoint: unsupported version '1'"),
        (b'{"version": true, "steps": []}', "corrupt checkpoint: unsupported version True"),
        (b'{"version": 2, "steps": []}', "corrupt checkpoint: unsupported version 2"),
        (b'{"version": 1, "steps": {}}', "corrupt checkpoint: steps is not a list"),
        (json.dumps({"version": 1, "steps": [good, {"name": "dedupe", "input": digest(["a"])}]}).encode(), "corrupt checkpoint: bad entry 2"),
        (json.dumps({"version": 1, "steps": [dict(good, extra=1)]}).encode(), "corrupt checkpoint: bad entry 1"),
        (json.dumps({"version": 1, "steps": [dict(good, input=digest(["a"]).upper())]}).encode(), "corrupt checkpoint: bad entry 1"),
        (json.dumps({"version": 1, "steps": [dict(good, name=7)]}).encode(), "corrupt checkpoint: bad entry 1"),
        (json.dumps({"version": 1, "steps": [good, "dedupe"]}).encode(), "corrupt checkpoint: bad entry 2"),
    ]
    ck = tmp_path / "run.ckpt"
    for raw, message in cases:
        c = Counter()
        ck.write_bytes(raw)
        with pytest.raises(CheckpointError) as exc:
            words(c).run(["a"], checkpoint=ck, resume=True)
        assert (str(exc.value), c.calls) == (message, []), raw


def test_an_output_that_is_not_json_keeps_the_earlier_entries(tmp_path):
    from stagerun.errors import CheckpointError

    ck = tmp_path / "run.ckpt"
    c = Counter()
    p = Pipeline([c.step("lower", lambda d: [s.lower() for s in d]), c.step("bag", set), c.step("count", len)])
    with pytest.raises(CheckpointError) as exc:
        p.run(["a"], checkpoint=ck)
    assert str(exc.value) == "step 'bag' output is not JSON-serialisable"
    assert c.calls == ["lower", "bag"]
    assert [e["name"] for e in entries(ck)["steps"]] == ["lower"]
    assert p.run(["a"]) == 1


def run_cli(argv):
    out, err = io.StringIO(), io.StringIO()
    return cli.main(argv, stdout=out, stderr=err), out.getvalue(), err.getvalue()


def test_cli_checkpoint_and_resume(tmp_path):
    spec = tmp_path / "w.spec"
    spec.write_text("strip\nlower\ncount\n")
    data = tmp_path / "in.json"
    data.write_text(json.dumps([" A", "a"]))
    out, ck = tmp_path / "out.json", tmp_path / "w.ckpt"
    args = ["run", str(spec), str(data), str(out), "--checkpoint", str(ck)]
    assert run_cli(args) == (0, "ran strip\nran lower\nran count\n", "")
    assert json.loads(out.read_text()) == {"a": 2}
    out.unlink()
    assert run_cli(args + ["--resume"]) == (0, "reused strip\nreused lower\nreused count\n", "")
    assert json.loads(out.read_text()) == {"a": 2}
    assert run_cli(["run", str(spec), str(data), str(out)]) == (0, "", "")


def test_cli_errors(tmp_path):
    spec = tmp_path / "w.spec"
    spec.write_text("strip\n")
    data = tmp_path / "in.json"
    data.write_text("[]")
    out, ck = tmp_path / "out.json", tmp_path / "w.ckpt"
    assert run_cli(["run", str(spec), str(data), str(out), "--resume"]) == (2, "", "stagerun: --resume needs --checkpoint\n")
    ck.write_text("[]")
    assert run_cli(["run", str(spec), str(data), str(out), "--checkpoint", str(ck), "--resume"]) == (
        1, "", "stagerun: corrupt checkpoint: not an object\n")
    assert not out.exists()
