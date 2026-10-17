import copy
import importlib
import io
import json
import os
import random
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _oracle_zq_jdiff as oracle  # noqa: E402
import _oracle_zq_jpatch as patch_ref  # noqa: E402

from docstore import Config, Conflict, InvalidId, NotFound, Store, cli  # noqa: E402
from docstore.canon import digest  # noqa: E402
from docstore.export import export_bundle, import_bundle  # noqa: E402


class _Missing(Exception):
    """Stands in for a name the implementation does not provide (every use fails)."""


def _name(module, name):
    try:
        return getattr(importlib.import_module(module), name)
    except (ImportError, AttributeError):
        if name[0].isupper():
            return type(name, (_Missing,), {})

        def missing(*args, **kwargs):
            raise AssertionError(f"{module}.{name} is not available")
        return missing


diff = _name("docstore.delta", "diff")
strict_equal = _name("docstore.delta", "strict_equal")
apply_patch = _name("docstore.patch", "apply_patch")
PatchError = _name("docstore.errors", "PatchError")


def canon(value):
    return json.dumps(value, sort_keys=True, default=repr)


def check_diff(a, b, label=""):
    """diff(a, b) equals the reference list exactly, leaves its inputs alone and round-trips."""
    a0, b0 = copy.deepcopy(a), copy.deepcopy(b)
    got = diff(a, b)
    want = oracle.diff(a0, b0)
    assert canon(got) == canon(want), f"{label} a={a0!r} b={b0!r}\n got={got!r}\nwant={want!r}"
    assert canon(a) == canon(a0) and canon(b) == canon(b0), f"{label} inputs modified"
    assert oracle.strict(patch_ref.apply(copy.deepcopy(a0), got), b0), f"{label} round trip"
    return got


# -- hand-written ---------------------------------------------------------------

def test_strict_equal_and_equal_values():
    assert strict_equal(1, 1) and strict_equal(1.5, 1.5) and strict_equal(0.0, -0.0) and strict_equal(None, None)
    assert not strict_equal(1, 1.0) and not strict_equal(1, True) and not strict_equal(1.0, True)
    assert not strict_equal(0, False) and not strict_equal(0, None) and not strict_equal(0.0, 0) and not strict_equal(False, None)
    assert strict_equal({"a": [1, {"b": 2}], "c": "x"}, {"c": "x", "a": [1, {"b": 2}]})
    assert not strict_equal({"a": [1]}, {"a": [1.0]}) and not strict_equal([1, 2], [2, 1]) and not strict_equal([], {})
    assert not strict_equal({"a": None}, {}) and not strict_equal("1", 1)
    assert diff({"a": [1, {"b": 2}]}, {"a": [1, {"b": 2}]}) == []
    assert diff({"x": 1, "y": 2}, {"y": 2, "x": 1}) == []
    assert diff([], []) == []


def test_objects_kinds_escapes_and_copies():
    a = {"b": 1, "d": {"x": 1}, "a": 0, "e": 5}
    b = {"c": 3, "d": {"x": 2, "y": None}, "a": 0, "b": 1}
    assert diff(a, b) == [
        {"op": "add", "path": "/c", "value": 3},
        {"op": "replace", "path": "/d/x", "value": 2},
        {"op": "add", "path": "/d/y", "value": None},
        {"op": "remove", "path": "/e"},
    ]
    assert diff({"v": 1}, {"v": 1.0}) == [{"op": "replace", "path": "/v", "value": 1.0}]
    assert diff({"v": True}, {"v": 1}) == [{"op": "replace", "path": "/v", "value": 1}]
    assert diff({"v": 0}, {"v": None}) == [{"op": "replace", "path": "/v", "value": None}]
    assert diff({"v": [1]}, {"v": {"0": 1}}) == [{"op": "replace", "path": "/v", "value": {"0": 1}}]
    assert diff([1], {"a": 1}) == [{"op": "replace", "path": "", "value": {"a": 1}}]
    assert diff(1, 2) == [{"op": "replace", "path": "", "value": 2}]
    a = {"a/b": {"m~n": [0]}, "": 1}
    b = {"a/b": {"m~n": [0, 1]}, "": 2, "~": None}
    assert diff(a, b) == [
        {"op": "replace", "path": "/", "value": 2},
        {"op": "add", "path": "/a~1b/m~0n/1", "value": 1},
        {"op": "add", "path": "/~0", "value": None},
    ]
    a, b = {"x": []}, {"x": [{"k": [1]}], "y": {"z": [2]}}
    b0 = copy.deepcopy(b)
    ops = diff(a, b)
    ops[0]["value"]["k"].append(9)
    ops[1]["value"]["z"].append(9)
    assert b == b0 and a == {"x": []}


def test_array_kept_pair_has_the_smallest_indexes_into_a():
    assert diff({"l": ["x", "y"]}, {"l": ["y", "x"]}) == [
        {"op": "remove", "path": "/l/1"},
        {"op": "add", "path": "/l/0", "value": "y"},
    ]
    assert diff(["x", "x", "y"], ["y", "x", "y", "y"]) == [
        {"op": "remove", "path": "/1"},
        {"op": "add", "path": "/0", "value": "y"},
        {"op": "add", "path": "/3", "value": "y"},
    ]
    assert diff(["x", "y", "x", "y"], ["y", "y", "x"]) == [
        {"op": "remove", "path": "/3"},
        {"op": "remove", "path": "/0"},
        {"op": "add", "path": "/1", "value": "y"},
    ]


def test_array_kept_pair_then_has_the_smallest_indexes_into_b():
    assert diff(["x"], ["x", "x"]) == [{"op": "add", "path": "/1", "value": "x"}]
    assert diff(["x", "y"], ["x", "y", "x", "y"]) == [
        {"op": "add", "path": "/2", "value": "x"},
        {"op": "add", "path": "/3", "value": "y"},
    ]
    assert diff(["x", "y", "x"], ["y", "x", "x", "x"]) == [
        {"op": "remove", "path": "/1"},
        {"op": "add", "path": "/0", "value": "y"},
        {"op": "add", "path": "/3", "value": "x"},
    ]


def test_array_removes_descend_and_adds_ascend():
    assert diff([1, 2, 3, 4, 5], [2, 9, 4, 8]) == [
        {"op": "remove", "path": "/4"},
        {"op": "remove", "path": "/2"},
        {"op": "remove", "path": "/0"},
        {"op": "add", "path": "/1", "value": 9},
        {"op": "add", "path": "/3", "value": 8},
    ]
    assert diff([1, 2], []) == [{"op": "remove", "path": "/1"}, {"op": "remove", "path": "/0"}]
    assert diff(["y", "x", "y", "x"], ["x", "x", "y"]) == [
        {"op": "remove", "path": "/3"},
        {"op": "remove", "path": "/0"},
        {"op": "add", "path": "/1", "value": "x"},
    ]


def test_array_elements_compare_strictly_and_whole():
    assert diff([1, True, 1.0], [1.0, 1]) == [
        {"op": "remove", "path": "/2"},
        {"op": "remove", "path": "/1"},
        {"op": "add", "path": "/0", "value": 1.0},
    ]
    assert diff([1, 1.0, 1], [1.0, 1, 1.0]) == [
        {"op": "remove", "path": "/2"},
        {"op": "add", "path": "/0", "value": 1.0},
    ]
    assert diff({"l": [{"a": 1, "b": 2}]}, {"l": [{"b": 2, "a": 1}, {"a": 2}]}) == [
        {"op": "add", "path": "/l/1", "value": {"a": 2}},
    ]
    assert diff([{"a": 1}], [{"a": 2}]) == [{"op": "remove", "path": "/0"}, {"op": "add", "path": "/0", "value": {"a": 2}}]


def test_store_revisions_and_revert_errors():
    s = Store()
    s.create("doc", {"v": 1})
    s.put("doc", {"v": 2})
    s.patch("doc", [{"op": "add", "path": "/w", "value": [1]}])
    s.patch("doc", [{"op": "remove", "path": "/w"}], dry_run=True)
    assert [s.at("doc", r) for r in (1, 2, 3)] == [{"v": 1}, {"v": 2}, {"v": 2, "w": [1]}]
    s.at("doc", 3)["w"].append(5)
    assert s.at("doc", 3) == {"v": 2, "w": [1]}
    for bad in (4, 0, True, "1", None):
        with pytest.raises(NotFound) as exc:
            s.at("doc", bad)
        assert str(exc.value) == f"no revision {bad!r} of 'doc'"
    with pytest.raises(NotFound, match="^no document 'zz'$"):
        s.at("zz", 1)
    with pytest.raises(InvalidId):
        s.at("BAD", 1)
    s.delete("doc")
    s.create("doc", {"new": True})
    with pytest.raises(NotFound, match="^no revision 2 of 'doc'$"):
        s.at("doc", 2)
    assert s.at("doc", 1) == {"new": True}
    t = Store()
    t.create("doc", {"old": 1})
    t.put("doc", {"old": 2})
    src = Store()
    src.create("doc", {"b": 1})
    import_bundle(t, export_bundle(src), replace=True)
    assert t.at("doc", 1) == {"b": 1}
    with pytest.raises(NotFound):
        t.at("doc", 2)
    _revert_errors()


def test_store_revert():
    s = Store(config=Config(max_ops=1))
    s.create("doc", {"l": ["a", "b", "c"], "k": 1})
    s.put("doc", {"l": ["c", "a", "x"], "k": 1.0, "n": None})
    result = s.revert("doc", 1)
    assert result == (3, {"l": ["a", "b", "c"], "k": 1}) and type(result.document["k"]) is int
    assert s.get("doc") == {"l": ["a", "b", "c"], "k": 1} and s.revision("doc") == 3
    ops = oracle.diff({"l": ["c", "a", "x"], "k": 1.0, "n": None}, {"l": ["a", "b", "c"], "k": 1})
    assert s.history.lines()[-1] == f"3\tdoc\trevert\t3\t{digest(s.get('doc'))}\tto=1 ops={len(ops)}"
    assert s.revert("doc", 3).revision == 4
    assert s.history.lines()[-1].endswith("\trevert\t4\t" + digest(s.get("doc")) + "\tto=3 ops=0")
    assert s.at("doc", 4) == s.at("doc", 1)


def _revert_errors():
    s = Store()
    s.create("doc", {"v": 1})
    s.put("doc", {"v": 2})
    with pytest.raises(InvalidId):
        s.revert("BAD", 99)
    with pytest.raises(NotFound, match="^no document 'zz'$"):
        s.revert("zz", 99, expected_rev=5)
    with pytest.raises(Conflict, match=r"^revision mismatch for 'doc': expected 1, found 2$"):
        s.revert("doc", 99, expected_rev=1)
    with pytest.raises(NotFound, match="^no revision 99 of 'doc'$"):
        s.revert("doc", 99, expected_rev=2)
    small = Store(s.storage, s.history, Config(max_bytes=5))
    with pytest.raises(PatchError, match=r"^result invalid: document is 7 bytes, limit 5$"):
        small.revert("doc", 1)
    assert s.revision("doc") == 2 and len(s.history.lines()) == 2 and s.get("doc") == {"v": 2}


def run(root, *args):
    out, err = io.StringIO(), io.StringIO()
    code = cli.main(["--root", str(root), *args], stdout=out, stderr=err)
    return code, out.getvalue(), err.getvalue()


def test_cli_diff_and_revert(tmp_path):
    f = tmp_path / "d.json"
    f.write_text(json.dumps({"l": ["x", "y", "x", "y"], "o": {"a": 1}}))
    run(tmp_path, "create", "d", str(f))
    f.write_text(json.dumps({"l": ["y", "y", "x"], "o": {"a": 1, "b/c": True}}))
    run(tmp_path, "put", "d", str(f))
    assert run(tmp_path, "diff", "d", "1") == (0, json.dumps([
        {"op": "remove", "path": "/l/3"}, {"op": "remove", "path": "/l/0"},
        {"op": "add", "path": "/l/1", "value": "y"}, {"op": "add", "path": "/o/b~1c", "value": True},
    ], separators=(",", ":")) + "\n", "")
    assert run(tmp_path, "diff", "d", "2") == (0, "[]\n", "")
    assert run(tmp_path, "diff", "d", "7") == (3, "", "docstore: no revision 7 of 'd'\n")
    assert run(tmp_path, "revert", "d", "1", "--rev", "1")[0] == 4
    assert run(tmp_path, "revert", "d", "1", "--rev", "2") == (0, "rev 3\n", "")
    assert run(tmp_path, "show", "d") == (0, '{"l":["x","y","x","y"],"o":{"a":1}}\n', "")
    assert run(tmp_path, "revert", "d", "9") == (3, "", "docstore: no revision 9 of 'd'\n")
    lines = (tmp_path / "history.log").read_text().splitlines()
    assert lines[-1].split("\t")[2:4] == ["revert", "3"] and lines[-1].endswith("to=1 ops=4")


# -- conformance over generated inputs ---------------------------------------------

def gen_array(rng, alphabet, max_len=8):
    return [copy.deepcopy(rng.choice(alphabet)) for _ in range(rng.randint(0, max_len))]


def mutate_array(rng, arr, alphabet):
    out = list(arr)
    for _ in range(rng.randint(0, 4)):
        r = rng.random()
        if r < 0.35 and out:
            del out[rng.randrange(len(out))]
        elif r < 0.7:
            out.insert(rng.randint(0, len(out)), copy.deepcopy(rng.choice(alphabet)))
        elif out:
            i, j = rng.randrange(len(out)), rng.randrange(len(out))
            out[i], out[j] = out[j], out[i]
    return out[:10]


def conform_arrays(seed, count, alphabet, max_len=8, related=0.6):
    rng = random.Random(seed)
    for n in range(count):
        a = gen_array(rng, alphabet, max_len)
        b = mutate_array(rng, a, alphabet) if rng.random() < related else gen_array(rng, alphabet, max_len)
        check_diff(a, b, f"sample {n}")


def test_conformance_arrays_two_symbols():
    conform_arrays(5001, 600, ["a", "b"])


def test_conformance_arrays_three_symbols():
    conform_arrays(5002, 600, ["a", "b", "c"])


def test_conformance_arrays_unrelated():
    conform_arrays(5003, 600, ["a", "b", "c", "d"], related=0.0)


def test_conformance_arrays_strict_kinds():
    conform_arrays(5004, 600, [1, 1.0, True, 0, 0.0, False, None, "1"])


def test_conformance_arrays_of_containers():
    alphabet = [{"a": 1, "b": 2}, {"b": 2, "a": 1}, {"a": 1}, {"a": 1.0}, [1], [1.0], [], {}, [True]]
    conform_arrays(5005, 600, alphabet)


def test_conformance_arrays_long_with_repeats():
    conform_arrays(5006, 300, ["a", "a", "a", "b"], max_len=10)


KEYS = ["a", "b", "c", "", "~", "/", "a/b", "~1", "-", "0"]
SCALARS = [0, 1, 1.0, True, False, None, "s", "t", 0.0]


def gen_value(rng, depth, list_alphabet):
    r = rng.random()
    if depth >= 4 or r < 0.35:
        return rng.choice(SCALARS)
    if r < 0.7:
        return {rng.choice(KEYS): gen_value(rng, depth + 1, list_alphabet) for _ in range(rng.randint(0, 4))}
    return gen_array(rng, list_alphabet, 6)


def mutate(rng, value, list_alphabet):
    if type(value) is dict:
        out = {}
        for k, v in value.items():
            r = rng.random()
            if r < 0.15:
                continue
            out[k] = mutate(rng, v, list_alphabet) if r < 0.6 else v
        if rng.random() < 0.3:
            out[rng.choice(KEYS)] = gen_value(rng, 2, list_alphabet)
        return out
    if type(value) is list:
        return mutate_array(rng, value, list_alphabet)
    return rng.choice([value, value, rng.choice(SCALARS)])


def conform_nested(seed, count, list_alphabet):
    rng = random.Random(seed)
    for n in range(count):
        a = gen_value(rng, 0, list_alphabet)
        b = mutate(rng, a, list_alphabet) if rng.random() < 0.8 else gen_value(rng, 0, list_alphabet)
        check_diff(a, b, f"sample {n}")


def _member(rng):
    return rng.choice(SCALARS) if rng.random() < 0.4 else gen_array(rng, ["x", "y"], 5)


def test_conformance_objects_with_array_members():
    rng = random.Random(5007)
    for n in range(800):
        a = {rng.choice(KEYS): _member(rng) for _ in range(rng.randint(0, 6))}
        b = {k: (mutate_array(rng, v, ["x", "y"]) if type(v) is list and rng.random() < 0.7 else _member(rng))
             for k, v in a.items() if rng.random() < 0.85}
        for _ in range(rng.randint(0, 2)):
            b[rng.choice(KEYS)] = _member(rng)
        check_diff(a, b, f"sample {n}")


def test_conformance_arrays_rotated_doubled_reversed():
    rng = random.Random(5013)
    for n in range(600):
        a = gen_array(rng, ["x", "y", "z"], 5)
        k = rng.randint(0, max(len(a) - 1, 0))
        b = rng.choice([a[k:] + a[:k], a + a, a[::-1], a[::-1] + a[:2], a[:2] + a[::-1]])[:10]
        check_diff(a, b, f"sample {n}")


def test_conformance_arrays_substitutions():
    rng = random.Random(5014)
    for n in range(600):
        a = gen_array(rng, ["x", "y"], 8)
        b = list(a)
        for _ in range(rng.randint(1, 3)):
            if b:
                b[rng.randrange(len(b))] = rng.choice(["x", "y", "z"])
        check_diff(a, b, f"sample {n}")


def test_conformance_documents_with_several_arrays():
    rng = random.Random(5015)
    for n in range(500):
        a = {k: gen_array(rng, ["x", "y", 1, 1.0], 6) for k in rng.sample(KEYS, rng.randint(1, 4))}
        a["o"] = {k: gen_array(rng, ["x", "y"], 5) for k in rng.sample(KEYS, rng.randint(1, 3))}
        b = mutate(rng, a, ["x", "y", 1, 1.0])
        check_diff(a, b, f"sample {n}")


def test_conformance_nested_documents():
    conform_nested(5008, 600, ["a", "b", 1, 1.0])


def test_conformance_nested_arrays_of_objects():
    conform_nested(5009, 500, [{"k": 1}, {"k": True}, {"k": 1, "j": 0}, ["a"], "a"])


def test_conformance_strict_equal():
    rng = random.Random(5010)
    alphabet = [1, 1.0, True, 0, False, None, "a", [1], {"k": 1}]
    for n in range(1000):
        a = gen_value(rng, 0, alphabet)
        b = mutate(rng, a, alphabet) if rng.random() < 0.5 else copy.deepcopy(a)
        if type(b) is dict and rng.random() < 0.5:
            b = dict(reversed(list(b.items())))
        assert bool(strict_equal(a, b)) == oracle.strict(a, b), f"sample {n}: {a!r} vs {b!r}"


def test_conformance_store_revert():
    rng = random.Random(5011)
    for n in range(150):
        s = Store()
        versions = [{"l": gen_array(rng, ["a", "b", "c"], 6), "o": gen_value(rng, 1, ["a", 1])}]
        s.create("doc", versions[0])
        for _ in range(rng.randint(1, 4)):
            nxt = mutate(rng, versions[-1], ["a", "b", "c"])
            if type(nxt) is not dict:
                nxt = {"v": nxt}
            versions.append(nxt)
            s.put("doc", nxt)
        r1, r2 = rng.randint(1, len(versions)), rng.randint(1, len(versions))
        got = diff(s.at("doc", r1), s.at("doc", r2))
        want = oracle.diff(copy.deepcopy(versions[r1 - 1]), copy.deepcopy(versions[r2 - 1]))
        assert canon(got) == canon(want), f"sample {n}: revisions {r1} -> {r2}: got={got!r} want={want!r}"
        target = rng.randint(1, len(versions))
        cur = versions[-1]
        want_ops = oracle.diff(copy.deepcopy(cur), copy.deepcopy(versions[target - 1]))
        result = s.revert("doc", target)
        assert result.revision == len(versions) + 1, f"sample {n}"
        assert oracle.strict(result.document, versions[target - 1]) and oracle.strict(s.get("doc"), versions[target - 1]), f"sample {n}"
        assert s.history.lines()[-1].endswith(f"\tto={target} ops={len(want_ops)}"), f"sample {n}: {s.history.lines()[-1]!r} want ops={len(want_ops)}"


def test_conformance_cli_diff(tmp_path):
    rng = random.Random(5012)
    for n in range(40):
        root = tmp_path / f"r{n}"
        root.mkdir()
        f = root / "d.json"
        a = {"l": gen_array(rng, ["a", "b"], 7), "o": gen_value(rng, 1, ["a", "b"])}
        b = {"l": mutate_array(rng, a["l"], ["a", "b"]), "o": mutate(rng, a["o"], ["a", "b"])}
        f.write_text(json.dumps(a))
        run(root, "create", "d", str(f))
        f.write_text(json.dumps(b))
        run(root, "put", "d", str(f))
        want = json.dumps(oracle.diff(a, b), sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
        assert run(root, "diff", "d", "1") == (0, want, ""), f"sample {n}: a={a!r} b={b!r}"
