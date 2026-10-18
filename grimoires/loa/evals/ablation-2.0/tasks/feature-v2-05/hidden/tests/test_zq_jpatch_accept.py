import copy
import io
import json

import pytest

import docstore
from docstore import Config, Conflict, InvalidId, NotFound, Store, cli
from docstore.canon import digest
from docstore.config import parse_config
import importlib


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

from docstore.errors import DocstoreError

PatchError = _name("docstore.errors", "PatchError")
PointerError = _name("docstore.errors", "PointerError")
PatchResult = _name("docstore.patch", "PatchResult")
apply_patch = _name("docstore.patch", "apply_patch")
json_equal = _name("docstore.patch", "json_equal")
format_pointer = _name("docstore.pointer", "format_pointer")
parse_pointer = _name("docstore.pointer", "parse_pointer")
resolve = _name("docstore.pointer", "resolve")


def perr(fn, *args, **kw):
    with pytest.raises(PatchError) as exc:
        fn(*args, **kw)
    assert type(exc.value) is PatchError
    return str(exc.value)


def ptrerr(fn, *args):
    with pytest.raises(PointerError) as exc:
        fn(*args)
    return str(exc.value)


# -- pointers ---------------------------------------------------------------

def _h_parse_pointer_tokens():
    assert parse_pointer("") == []
    assert parse_pointer("/") == [""]
    assert parse_pointer("/a//b") == ["a", "", "b"]
    assert parse_pointer("/a~1b/~0") == ["a/b", "~"]
    assert parse_pointer("/~01") == ["~1"]
    assert parse_pointer("/~10") == ["/0"]


def _h_parse_pointer_errors():
    assert ptrerr(parse_pointer, "a/b") == "pointer must start with '/': 'a/b'"
    assert ptrerr(parse_pointer, "#/a") == "pointer must start with '/': '#/a'"
    assert ptrerr(parse_pointer, "/a~2") == "bad escape in pointer: '/a~2'"
    assert ptrerr(parse_pointer, "/x/a~") == "bad escape in pointer: '/x/a~'"
    assert ptrerr(parse_pointer, "/~/0") == "bad escape in pointer: '/~/0'"
    assert issubclass(PointerError, DocstoreError) and not issubclass(PatchError, PointerError)


def _h_format_pointer():
    assert format_pointer([]) == ""
    assert format_pointer([""]) == "/"
    assert format_pointer(["a/b", "~1", "", "~/"]) == "/a~1b/~01//~0~1"


def _h_resolve_object_members_take_any_token():
    doc = {"": 1, "-": 2, "01": 3, "a/b": {"m~n": 4}}
    assert resolve(doc, "/") == 1
    assert resolve(doc, "/-") == 2
    assert resolve(doc, "/01") == 3
    assert resolve(doc, "/a~1b/m~0n") == 4
    assert resolve(doc, "") is doc
    assert ptrerr(resolve, doc, "/x") == "path '/x' does not exist"


def _h_resolve_array_index_rules():
    doc = {"a": [10, 20, 30]}
    assert resolve(doc, "/a/0") == 10 and resolve(doc, "/a/2") == 30
    assert ptrerr(resolve, doc, "/a/01") == "invalid array index '01' in '/a/01'"
    assert ptrerr(resolve, doc, "/a/+1") == "invalid array index '+1' in '/a/+1'"
    assert ptrerr(resolve, doc, "/a/") == "invalid array index '' in '/a/'"
    assert ptrerr(resolve, doc, "/a/-") == "index '-' out of range in '/a/-'"
    assert ptrerr(resolve, doc, "/a/3") == "index '3' out of range in '/a/3'"
    assert ptrerr(resolve, doc, "/a/3/x") == "index '3' out of range in '/a/3/x'"


def _h_resolve_through_scalars_and_identity():
    doc = {"s": "text", "n": None, "l": [[1]]}
    assert ptrerr(resolve, doc, "/s/0") == "path '/s/0' does not exist"
    assert ptrerr(resolve, doc, "/n/x/y") == "path '/n/x/y' does not exist"
    assert ptrerr(resolve, doc, "/q/x/y") == "path '/q/x/y' does not exist"
    assert resolve(doc, "/l/0") is doc["l"][0]


# -- patch checks -----------------------------------------------------------

def _h_patch_must_be_a_list_and_respects_max_ops():
    assert perr(apply_patch, {}, {"op": "add"}) == "patch must be a list of operations"
    ops = [{"op": "test", "path": "", "value": {}}] * 3
    assert perr(apply_patch, {}, ops, 2) == "too many operations: 3 > 2"
    assert apply_patch({}, ops, 3) == {}
    assert perr(apply_patch, {}, [{"op": "test", "path": "", "value": {}}] * 101) == "too many operations: 101 > 100"
    doc = {"a": [1]}
    out = apply_patch(doc, [])
    assert out == doc and out is not doc and out["a"] is not doc["a"]


def _h_operation_shape_errors():
    assert perr(apply_patch, {}, [["add"]]) == "op 0: operation must be an object"
    assert perr(apply_patch, {}, [{"path": "/a"}]) == "op 0: missing 'op'"
    assert perr(apply_patch, {}, [{"op": "Add", "path": "/a"}]) == "op 0: unknown op 'Add'"
    assert perr(apply_patch, {}, [{"op": 5}]) == "op 0: unknown op 5"
    assert perr(apply_patch, {}, [{"op": None}]) == "op 0: unknown op None"


def _h_path_member_errors():
    t = {"op": "test", "path": "", "value": {}}
    assert perr(apply_patch, {}, [t, {"op": "remove"}]) == "op 1 (remove): missing 'path'"
    assert perr(apply_patch, {}, [{"op": "remove", "path": 3}]) == "op 0 (remove): 'path' must be a string"
    assert perr(apply_patch, {}, [{"op": "remove", "path": "a"}]) == "op 0 (remove): pointer must start with '/': 'a'"
    assert perr(apply_patch, {}, [{"op": "remove", "path": "/a~"}]) == "op 0 (remove): bad escape in pointer: '/a~'"


def _h_from_member_errors():
    assert perr(apply_patch, {}, [{"op": "move", "path": "/a"}]) == "op 0 (move): missing 'from'"
    assert perr(apply_patch, {}, [{"op": "copy", "path": "/a", "from": ["x"]}]) == "op 0 (copy): 'from' must be a string"
    assert perr(apply_patch, {}, [{"op": "copy", "path": "/a", "from": "/~2"}]) == "op 0 (copy): bad escape in pointer: '/~2'"
    assert perr(apply_patch, {}, [{"op": "move", "path": "a", "from": "b"}]) == "op 0 (move): pointer must start with '/': 'a'"


def _h_value_member_rules():
    assert perr(apply_patch, {}, [{"op": "add", "path": "/a"}]) == "op 0 (add): missing 'value'"
    assert perr(apply_patch, {}, [{"op": "test", "path": "/a"}]) == "op 0 (test): missing 'value'"
    assert apply_patch({}, [{"op": "add", "path": "/a", "value": None}]) == {"a": None}
    assert apply_patch({"a": 1}, [{"op": "remove", "path": "/a", "value": 9, "from": 3}]) == {}
    assert apply_patch({}, [{"op": "add", "path": "/a", "value": 1, "comment": "x"}]) == {"a": 1}


def _h_every_operation_is_checked_before_any_is_applied():
    ops = [{"op": "remove", "path": "/missing"}, {"op": "add", "path": "/x", "value": 1}, {"op": "copy", "path": "/y"}]
    assert perr(apply_patch, {}, ops) == "op 2 (copy): missing 'from'"
    ops[2]["from"] = "/x"
    assert perr(apply_patch, {}, ops) == "op 0 (remove): path '/missing' does not exist"


# -- operations -------------------------------------------------------------

def _h_add_on_objects_and_root():
    assert apply_patch({"a": 1}, [{"op": "add", "path": "/a", "value": 2}]) == {"a": 2}
    assert apply_patch({}, [{"op": "add", "path": "/", "value": 2}]) == {"": 2}
    assert apply_patch({"a": 1}, [{"op": "add", "path": "", "value": {"b": [1]}}]) == {"b": [1]}
    assert apply_patch({}, [{"op": "add", "path": "/-", "value": 1}]) == {"-": 1}


def _h_add_on_arrays():
    doc = {"a": [1, 2]}
    assert apply_patch(doc, [{"op": "add", "path": "/a/-", "value": 3}]) == {"a": [1, 2, 3]}
    assert apply_patch(doc, [{"op": "add", "path": "/a/0", "value": 0}]) == {"a": [0, 1, 2]}
    assert apply_patch(doc, [{"op": "add", "path": "/a/2", "value": 3}]) == {"a": [1, 2, 3]}
    assert perr(apply_patch, doc, [{"op": "add", "path": "/a/3", "value": 3}]) == "op 0 (add): index '3' out of range in '/a/3'"
    assert perr(apply_patch, doc, [{"op": "add", "path": "/a/01", "value": 3}]) == "op 0 (add): invalid array index '01' in '/a/01'"
    assert perr(apply_patch, doc, [{"op": "add", "path": "/a/-/x", "value": 3}]) == "op 0 (add): index '-' out of range in '/a/-/x'"


def _h_add_needs_an_existing_container():
    doc = {"s": "x", "o": {}}
    assert perr(apply_patch, doc, [{"op": "add", "path": "/s/k", "value": 1}]) == "op 0 (add): path '/s/k' does not exist"
    assert perr(apply_patch, doc, [{"op": "add", "path": "/o/p/q", "value": 1}]) == "op 0 (add): path '/o/p/q' does not exist"
    assert apply_patch(doc, [{"op": "add", "path": "/o/p", "value": 1}]) == {"s": "x", "o": {"p": 1}}


def _h_remove():
    assert apply_patch({"a": [1, 2, 3]}, [{"op": "remove", "path": "/a/0"}]) == {"a": [2, 3]}
    assert perr(apply_patch, {"a": 1}, [{"op": "remove", "path": "/b"}]) == "op 0 (remove): path '/b' does not exist"
    assert perr(apply_patch, {"a": 1}, [{"op": "remove", "path": ""}]) == "op 0 (remove): cannot remove the document root"
    assert perr(apply_patch, {"a": [1]}, [{"op": "remove", "path": "/a/-"}]) == "op 0 (remove): index '-' out of range in '/a/-'"
    assert perr(apply_patch, {"a": [1]}, [{"op": "remove", "path": "/a/1"}]) == "op 0 (remove): index '1' out of range in '/a/1'"


def _h_replace():
    assert apply_patch({"a": [1, 2]}, [{"op": "replace", "path": "/a/1", "value": 5}]) == {"a": [1, 5]}
    assert perr(apply_patch, {}, [{"op": "replace", "path": "/a", "value": 1}]) == "op 0 (replace): path '/a' does not exist"
    assert perr(apply_patch, {"a": [1]}, [{"op": "replace", "path": "/a/1", "value": 1}]) == "op 0 (replace): index '1' out of range in '/a/1'"
    assert perr(apply_patch, {"a": [1]}, [{"op": "replace", "path": "/a/-", "value": 1}]) == "op 0 (replace): index '-' out of range in '/a/-'"
    assert apply_patch({"a": 1}, [{"op": "replace", "path": "", "value": {"z": 0}}]) == {"z": 0}


def _h_move_within_an_array_uses_the_document_after_removal():
    doc = {"a": ["x", "y", "z"]}
    assert apply_patch(doc, [{"op": "move", "from": "/a/0", "path": "/a/2"}]) == {"a": ["y", "z", "x"]}
    assert apply_patch(doc, [{"op": "move", "from": "/a/2", "path": "/a/0"}]) == {"a": ["z", "x", "y"]}
    assert apply_patch(doc, [{"op": "move", "from": "/a/0", "path": "/a/-"}]) == {"a": ["y", "z", "x"]}
    assert perr(apply_patch, doc, [{"op": "move", "from": "/a/0", "path": "/a/3"}]) == "op 0 (move): index '3' out of range in '/a/3'"


def _h_move_same_path_and_into_child():
    doc = {"a": {"b": 1}}
    assert apply_patch(doc, [{"op": "move", "from": "/a", "path": "/a"}]) == doc
    assert perr(apply_patch, doc, [{"op": "move", "from": "/q", "path": "/q"}]) == "op 0 (move): path '/q' does not exist"
    assert perr(apply_patch, doc, [{"op": "move", "from": "/a", "path": "/a/c"}]) == "op 0 (move): cannot move '/a' into its own child '/a/c'"
    assert perr(apply_patch, doc, [{"op": "move", "from": "", "path": "/x"}]) == "op 0 (move): cannot move '' into its own child '/x'"
    assert apply_patch(doc, [{"op": "move", "from": "/a", "path": "/ab"}]) == {"ab": {"b": 1}}
    assert apply_patch(doc, [{"op": "move", "from": "/a/b", "path": "/a"}]) == {"a": 1}


def _h_copy_is_deep():
    out = apply_patch({"a": {"l": [1]}}, [
        {"op": "copy", "from": "/a", "path": "/b"},
        {"op": "add", "path": "/b/l/-", "value": 2},
        {"op": "copy", "from": "/a/l", "path": "/a/l/0"},
    ])
    assert out == {"a": {"l": [[1], 1]}, "b": {"l": [1, 2]}}
    assert perr(apply_patch, {}, [{"op": "copy", "from": "/x", "path": "/y"}]) == "op 0 (copy): path '/x' does not exist"


def _h_test_operation_uses_json_equality():
    doc = {"n": 1, "f": 1.0, "t": True, "z": 0, "l": [1, {"a": 1, "b": 2}]}
    assert apply_patch(doc, [{"op": "test", "path": "/n", "value": 1.0}, {"op": "test", "path": "/f", "value": 1}]) == doc
    assert perr(apply_patch, doc, [{"op": "test", "path": "/t", "value": 1}]) == "op 0 (test): test failed at '/t'"
    assert perr(apply_patch, doc, [{"op": "test", "path": "/z", "value": False}]) == "op 0 (test): test failed at '/z'"
    assert perr(apply_patch, doc, [{"op": "test", "path": "/l", "value": [True, {"b": 2, "a": 1}]}]) == "op 0 (test): test failed at '/l'"
    assert apply_patch(doc, [{"op": "test", "path": "/l", "value": [1.0, {"b": 2, "a": 1}]}]) == doc
    assert perr(apply_patch, doc, [{"op": "test", "path": "/q", "value": None}]) == "op 0 (test): path '/q' does not exist"
    assert perr(apply_patch, doc, [{"op": "test", "path": "", "value": {}}]) == "op 0 (test): test failed at ''"


def _h_json_equal():
    assert json_equal(1, 1.0) and json_equal(-0.0, 0) and json_equal(None, None)
    assert not json_equal(True, 1) and not json_equal(0, False) and not json_equal(None, False)
    assert not json_equal([1, 2], [2, 1]) and not json_equal({"a": 1}, {"a": 1, "b": None})
    assert json_equal({"a": [1, {"b": 2.0}]}, {"a": [1.0, {"b": 2}]})
    assert not json_equal({"a": [True]}, {"a": [1]}) and not json_equal("1", 1) and not json_equal([], {})


def _h_inputs_are_never_modified_and_failure_is_atomic():
    doc = {"a": [1, 2], "o": {"k": "v"}}
    ops = [{"op": "add", "path": "/a/-", "value": {"n": [3]}}, {"op": "remove", "path": "/o/k"}, {"op": "remove", "path": "/zz"}]
    doc0, ops0 = copy.deepcopy(doc), copy.deepcopy(ops)
    assert perr(apply_patch, doc, ops) == "op 2 (remove): path '/zz' does not exist"
    assert doc == doc0 and ops == ops0
    out = apply_patch(doc, ops[:2])
    assert doc == doc0 and ops == ops0
    ops[0]["value"]["n"].append(4)
    assert out == {"a": [1, 2, {"n": [3]}], "o": {}}


# -- store -------------------------------------------------------------------

def make_store(**config):
    s = Store(config=Config(**config))
    s.create("doc", {"a": [1, 2], "o": {"k": "v"}})
    return s


def _h_store_get_with_pointer():
    s = make_store()
    assert s.get("doc", "/a/1") == 2 and s.get("doc") == {"a": [1, 2], "o": {"k": "v"}}
    got = s.get("doc", "/a")
    got.append(9)
    assert s.get("doc", "") == {"a": [1, 2], "o": {"k": "v"}}
    with pytest.raises(PointerError, match=r"^index '5' out of range in '/a/5'$"):
        s.get("doc", "/a/5")
    with pytest.raises(NotFound):
        s.get("nope", "bad")
    with pytest.raises(InvalidId):
        s.get("BAD", "bad")


def _h_store_patch_success_and_history():
    s = make_store()
    result = s.patch("doc", [{"op": "add", "path": "/a/-", "value": 3}, {"op": "remove", "path": "/o"}])
    assert isinstance(result, PatchResult) and result == (2, {"a": [1, 2, 3]})
    assert result.revision == 2 and result.document == {"a": [1, 2, 3]}
    assert s.revision("doc") == 2 and s.get("doc") == {"a": [1, 2, 3]}
    result.document["a"].append(7)
    assert s.get("doc") == {"a": [1, 2, 3]}
    assert s.history.lines()[-1] == f"2\tdoc\tpatch\t2\t{digest({'a': [1, 2, 3]})}\tops=2"
    entry = s.history.entries("doc")[-1]
    assert (entry.action, entry.rev, entry.detail) == ("patch", 2, "ops=2")


def _h_store_patch_that_changes_nothing_still_bumps():
    s = make_store()
    assert s.patch("doc", [{"op": "test", "path": "/a/0", "value": 1.0}]).revision == 2
    assert s.patch("doc", []) == (3, {"a": [1, 2], "o": {"k": "v"}})
    assert s.history.lines()[-1].endswith("\tpatch\t3\t" + digest(s.get("doc")) + "\tops=0")


def _h_store_patch_check_order_and_atomicity():
    s = make_store()
    with pytest.raises(InvalidId):
        s.patch("BAD", "not a list")
    with pytest.raises(NotFound):
        s.patch("nope", "not a list", expected_rev=7)
    with pytest.raises(Conflict) as exc:
        s.patch("doc", "not a list", expected_rev=7)
    assert str(exc.value) == "revision mismatch for 'doc': expected 7, found 1"
    assert perr(s.patch, "doc", [{"op": "add", "path": "/x", "value": 1}, {"op": "test", "path": "/x", "value": 2}],
                expected_rev=1) == "op 1 (test): test failed at '/x'"
    assert s.revision("doc") == 1 and s.get("doc") == {"a": [1, 2], "o": {"k": "v"}} and len(s.history.lines()) == 1


def _h_store_patch_validates_the_result():
    s = make_store(max_depth=3)
    assert perr(s.patch, "doc", [{"op": "replace", "path": "", "value": [1]}]) == "result invalid: document root must be an object"
    assert perr(s.patch, "doc", [{"op": "add", "path": "/o/d", "value": {"e": {}}}]) == "result invalid: nesting deeper than 3 at $.o.d.e"
    assert perr(s.patch, "doc", [{"op": "add", "path": "/a/0", "value": float("nan")}]) == "result invalid: non-finite number at $.a[0]"
    assert s.patch("doc", [{"op": "add", "path": "/o/d", "value": {"e": 1}}]).revision == 2
    assert len(s.history.lines()) == 2


def _h_store_patch_dry_run():
    s = make_store()
    result = s.patch("doc", [{"op": "replace", "path": "/o/k", "value": "w"}], expected_rev=1, dry_run=True)
    assert result == (2, {"a": [1, 2], "o": {"k": "w"}})
    assert s.revision("doc") == 1 and s.get("doc", "/o/k") == "v" and len(s.history.lines()) == 1


def _h_max_ops_config():
    assert Config().max_ops == 100
    c = parse_config("max_ops = 2\n")
    assert c.max_ops == 2
    with pytest.raises(docstore.ConfigError, match="max_ops must be a positive integer"):
        parse_config("max_ops = 0\n")
    s = Store(config=c)
    s.create("d", {})
    assert perr(s.patch, "d", [{"op": "test", "path": "", "value": {}}] * 3) == "too many operations: 3 > 2"


def _h_package_exports():
    assert docstore.PointerError is PointerError and docstore.PatchError is PatchError
    assert docstore.PatchResult is PatchResult


# -- command line -------------------------------------------------------------

def run(root, *args):
    out, err = io.StringIO(), io.StringIO()
    code = cli.main(["--root", str(root), *args], stdout=out, stderr=err)
    return code, out.getvalue(), err.getvalue()


def _h_cli_get(tmp_path):
    f = tmp_path / "d.json"
    f.write_text(json.dumps({"b": {"x/y": [1, None]}, "a": 1}))
    run(tmp_path, "create", "d", str(f))
    assert run(tmp_path, "get", "d", "/b/x~1y") == (0, "[1,null]\n", "")
    assert run(tmp_path, "get", "d", "") == (0, '{"a":1,"b":{"x/y":[1,null]}}\n', "")
    assert run(tmp_path, "get", "d", "/b/x~1y/01") == (6, "", "docstore: invalid array index '01' in '/b/x~1y/01'\n")
    assert run(tmp_path, "get", "zz", "/a")[0] == 3


def _h_cli_patch(tmp_path):
    f = tmp_path / "d.json"
    f.write_text(json.dumps({"a": [1]}))
    run(tmp_path, "create", "d", str(f))
    p = tmp_path / "p.json"
    p.write_text(json.dumps([{"op": "add", "path": "/a/0", "value": 0}]))
    assert run(tmp_path, "patch", "d", str(p), "--dry-run") == (0, '{"a":[0,1]}\n', "")
    assert run(tmp_path, "show", "d") == (0, '{"a":[1]}\n', "")
    assert run(tmp_path, "patch", "d", str(p), "--rev", "1") == (0, "rev 2\n", "")
    assert run(tmp_path, "show", "d") == (0, '{"a":[0,1]}\n', "")
    assert run(tmp_path, "patch", "d", str(p), "--rev", "1")[0] == 4
    lines = (tmp_path / "history.log").read_text().splitlines()
    assert lines[-1].split("\t")[2:] == ["patch", "2", digest({"a": [0, 1]}), "ops=1"]


def _h_cli_patch_errors(tmp_path):
    f = tmp_path / "d.json"
    f.write_text("{}")
    run(tmp_path, "create", "d", str(f))
    p = tmp_path / "p.json"
    p.write_text(json.dumps([{"op": "remove", "path": "/x"}]))
    assert run(tmp_path, "patch", "d", str(p)) == (6, "", "docstore: op 0 (remove): path '/x' does not exist\n")
    p.write_text(json.dumps({"op": "remove"}))
    assert run(tmp_path, "patch", "d", str(p)) == (6, "", "docstore: patch must be a list of operations\n")
    p.write_text("[")
    code, out, err = run(tmp_path, "patch", "d", str(p))
    assert code == 5 and err.startswith(f"docstore: {p}: invalid JSON:")
    assert run(tmp_path, "list") == (0, "d 1\n", "")


# -- conformance over generated inputs ----------------------------------------
import copy
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _oracle_zq_jpatch as ref  # noqa: E402

from docstore import Store  # noqa: E402
from docstore.errors import DocstoreError  # noqa: E402

import importlib  # noqa: E402


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

apply_patch = _name("docstore.patch", "apply_patch")
json_equal = _name("docstore.patch", "json_equal")
format_pointer = _name("docstore.pointer", "format_pointer")
parse_pointer = _name("docstore.pointer", "parse_pointer")
resolve = _name("docstore.pointer", "resolve")

KEYS = ["a", "b", "c", "", "-", "0", "01", "1", "~", "/", "~1", "a/b", "m~n", "x y"]
SCALARS = [0, 1, 1.0, 2, 2.5, -0.0, True, False, None, "s", "", "1", "true"]
BAD_INDEX = ["-", "01", "00", "+1", " 1", "", "x", "1.0", "99999999999999999999", "-1"]


def canon(value):
    return json.dumps(value, sort_keys=True, default=repr)


def mine(fn, *args):
    try:
        return ("ok", fn(*args))
    except DocstoreError as exc:
        return ("err", type(exc).__name__, str(exc))
    except Exception as exc:  # any other exception is a deviation
        return ("crash", type(exc).__name__, str(exc))


def same(a, b):
    if a[0] != b[0]:
        return False
    if a[0] == "ok":
        return canon(a[1]) == canon(b[1])
    return a[1:] == b[1:]


def gen_value(rng, depth=0):
    r = rng.random()
    if depth >= 3 or r < 0.4:
        return rng.choice(SCALARS)
    if r < 0.7:
        return {rng.choice(KEYS): gen_value(rng, depth + 1) for _ in range(rng.randint(0, 4))}
    return [gen_value(rng, depth + 1) for _ in range(rng.randint(0, 4))]


def gen_doc(rng):
    return {rng.choice(KEYS): gen_value(rng, 1) for _ in range(rng.randint(1, 5))}


def paths(doc, prefix=()):
    """Every existing token path (as tuples) in doc."""
    out = [prefix]
    if type(doc) is dict:
        for k, v in doc.items():
            out += paths(v, prefix + (k,))
    elif type(doc) is list:
        for i, v in enumerate(doc):
            out += paths(v, prefix + (str(i),))
    return out


def node(doc, toks):
    for t in toks:
        doc = doc[t] if type(doc) is dict else doc[int(t)]
    return doc


def gen_pointer(rng, doc, allow_bad_syntax=True):
    toks = list(rng.choice(paths(doc)))
    r = rng.random()
    if r < 0.25:
        pass
    elif r < 0.45:
        toks.append(rng.choice(KEYS + BAD_INDEX + [str(rng.randint(0, 5))]))
    elif r < 0.65 and toks:
        parent = node(doc, toks[:-1])
        if type(parent) is list:
            toks[-1] = rng.choice(BAD_INDEX + [str(len(parent)), str(len(parent) + 1)])
        else:
            toks[-1] = rng.choice(KEYS)
    elif r < 0.8 and toks:
        toks.insert(rng.randint(0, len(toks)), rng.choice(KEYS + BAD_INDEX))
    elif allow_bad_syntax and r < 0.88:
        return rng.choice(["a", "a/b", "#/a", "/a~2", "/a~", "/~", "~1", "/x/~3y", " /a"])
    text = ref.fmt(toks)
    if allow_bad_syntax and rng.random() < 0.05:
        text = text + "~"
    return text


def gen_op(rng, doc, names=None, valid_shape=True):
    name = rng.choice(names or list(ref.NAMES))
    op = {"op": name, "path": gen_pointer(rng, doc, allow_bad_syntax=not valid_shape)}
    if name in ("move", "copy"):
        op["from"] = gen_pointer(rng, doc, allow_bad_syntax=not valid_shape)
        if rng.random() < 0.25:
            op["path"] = op["from"] + rng.choice(["", "/a", "/0", "/-", "/b/c"])
    if name in ("add", "replace", "test"):
        op["value"] = gen_value(rng, 1)
    return op


def perturb(rng, value):
    """A value JSON-equal or almost JSON-equal to value."""
    t = type(value)
    if t is bool:
        return rng.choice([value, not value, int(value), float(value)])
    if t in (int, float):
        return rng.choice([value, float(value), int(value), value + 1, bool(value) if value in (0, 1) else value])
    if t is dict:
        items = list(value.items())
        rng.shuffle(items)
        out = {k: perturb(rng, v) if rng.random() < 0.5 else v for k, v in items}
        if rng.random() < 0.1:
            out[rng.choice(KEYS)] = None
        return out
    if t is list:
        out = [perturb(rng, v) if rng.random() < 0.5 else v for v in value]
        if len(out) > 1 and rng.random() < 0.15:
            out[0], out[1] = out[1], out[0]
        return out
    return rng.choice([value, None, "s", 0, False])


def run_patch_samples(seed, count, make_ops):
    rng = random.Random(seed)
    for n in range(count):
        doc = gen_doc(rng)
        ops = make_ops(rng, doc)
        doc0, ops0 = copy.deepcopy(doc), copy.deepcopy(ops)
        got = mine(apply_patch, doc, ops)
        want = ref.outcome(ref.apply, copy.deepcopy(doc0), copy.deepcopy(ops0))
        assert same(got, want), f"sample {n}: doc={doc0!r} ops={ops0!r} got={got!r} want={want!r}"
        assert canon(doc) == canon(doc0) and canon(ops) == canon(ops0), f"sample {n}: inputs modified"


def _c_conformance_pointer_parse_and_format():
    rng = random.Random(6901)
    alphabet = ["/", "/", "~", "0", "1", "2", "a", "-"]
    for n in range(2000):
        text = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 8)))
        got, want = mine(parse_pointer, text), ref.outcome(ref.parse, text)
        assert same(got, want), f"parse {text!r}: got={got!r} want={want!r}"
        toks = ["".join(rng.choice(["~", "/", "0", "1", "a"]) for _ in range(rng.randint(0, 4))) for _ in range(rng.randint(0, 3))]
        assert format_pointer(toks) == ref.fmt(toks), f"format {toks!r}"
        assert parse_pointer(ref.fmt(toks)) == toks, f"round trip {toks!r}"


def _c_conformance_resolve():
    rng = random.Random(1001)
    for n in range(1500):
        doc = gen_doc(rng)
        ptr = gen_pointer(rng, doc)
        got, want = mine(resolve, doc, ptr), ref.outcome(ref.resolve, doc, ptr)
        assert same(got, want), f"sample {n}: doc={doc!r} ptr={ptr!r} got={got!r} want={want!r}"


def _c_conformance_add():
    run_patch_samples(2001, 1500, lambda rng, doc: [gen_op(rng, doc, ["add"])])


def _c_conformance_remove_and_replace():
    run_patch_samples(2002, 1500, lambda rng, doc: [gen_op(rng, doc, ["remove", "replace"])])


def _c_conformance_move():
    run_patch_samples(2003, 1500, lambda rng, doc: [gen_op(rng, doc, ["move"])])


def _c_conformance_copy_then_change():
    def make(rng, doc):
        ops = [gen_op(rng, doc, ["copy"])]
        for _ in range(rng.randint(1, 3)):
            ops.append(gen_op(rng, doc, ["add", "replace", "remove"]))
        return ops
    run_patch_samples(2004, 1500, make)


def _c_conformance_test_operation():
    def make(rng, doc):
        toks = list(rng.choice(paths(doc)))
        target = node(doc, toks)
        return [{"op": "test", "path": ref.fmt(toks), "value": perturb(rng, target)}]
    run_patch_samples(2005, 2000, make)


def _c_conformance_json_equal():
    rng = random.Random(2006)
    for n in range(2000):
        a = gen_value(rng)
        b = perturb(rng, a) if rng.random() < 0.8 else gen_value(rng)
        assert bool(json_equal(a, b)) == ref.equal(a, b), f"{a!r} vs {b!r}"


def _c_conformance_operation_checks():
    def make(rng, doc):
        ops = [gen_op(rng, doc, valid_shape=False) for _ in range(rng.randint(1, 4))]
        k = rng.randrange(len(ops))
        damage = rng.randrange(9)
        op = ops[k]
        if damage == 0:
            ops[k] = rng.choice([[], "add", 1, None])
        elif damage == 1:
            op.pop("op")
        elif damage == 2:
            op["op"] = rng.choice(["Add", "ADD", "delete", 3, None, True, ["add"], " add"])
        elif damage == 3:
            op.pop("path")
        elif damage == 4:
            op["path"] = rng.choice([1, None, ["/a"], {"p": "/a"}, False])
        elif damage == 5:
            op.pop("from", None)
        elif damage == 6:
            op["from"] = rng.choice([0, None, ["/a"]])
        elif damage == 7:
            op.pop("value", None)
        else:
            op["value"] = None
        return ops
    run_patch_samples(2007, 2000, make)


def _c_conformance_mixed_sequences_share_nothing():
    rng = random.Random(2008)
    for n in range(1500):
        doc = gen_doc(rng)
        ops = []
        cur = doc
        for _ in range(rng.randint(1, 6)):
            ops.append(gen_op(rng, cur))
            step = ref.outcome(ref.apply, copy.deepcopy(cur), [ops[-1]])
            if step[0] == "ok" and type(step[1]) in (dict, list) and step[1] not in ([], {}):
                cur = step[1]
        doc0, ops0 = copy.deepcopy(doc), copy.deepcopy(ops)
        got = mine(apply_patch, doc, ops)
        want = ref.outcome(ref.apply, copy.deepcopy(doc0), copy.deepcopy(ops0))
        assert same(got, want), f"sample {n}: doc={doc0!r} ops={ops0!r} got={got!r} want={want!r}"
        assert canon(doc) == canon(doc0) and canon(ops) == canon(ops0), f"sample {n}: inputs modified"
        if got[0] == "ok":
            mine_ids = {id(x) for x in _containers(got[1])}
            theirs = {id(x) for x in _containers(doc)} | {id(x) for x in _containers(ops)}
            assert not (mine_ids & theirs), f"sample {n}: result shares structure with the inputs"


def _containers(value):
    if type(value) in (dict, list):
        yield value
        for v in (value.values() if type(value) is dict else value):
            yield from _containers(v)


def _c_conformance_store_patch():
    rng = random.Random(2009)
    store = Store()
    docs = {}
    for i in range(5):
        docs[f"d{i}"] = gen_doc(rng)
        store.create(f"d{i}", docs[f"d{i}"])
    revs = {k: 1 for k in docs}
    lines = 5
    for n in range(800):
        doc_id = rng.choice(sorted(docs))
        cur = docs[doc_id]
        ops = [gen_op(rng, cur) for _ in range(rng.randint(0, 3))]
        dry = rng.random() < 0.2
        want = ref.outcome(ref.apply, copy.deepcopy(cur), copy.deepcopy(ops))
        if want[0] == "ok" and type(want[1]) is not dict:
            want = ("err", "PatchError", "result invalid: document root must be an object")
        got = mine(store.patch, doc_id, ops, None, dry)
        if want[0] == "ok":
            assert got[0] == "ok" and len(got[1]) == 2, f"sample {n}: got={got!r} want={want!r}"
            assert got[1][0] == revs[doc_id] + 1 and canon(got[1][1]) == canon(want[1]), f"sample {n}: got={got!r} want={want!r}"
            if not dry:
                docs[doc_id] = want[1]
                revs[doc_id] += 1
                lines += 1
        else:
            assert same(got, want), f"sample {n}: doc={cur!r} ops={ops!r} got={got!r} want={want!r}"
        assert store.revision(doc_id) == revs[doc_id] and canon(store.get(doc_id)) == canon(docs[doc_id]), f"sample {n}"
        assert len(store.history.lines()) == lines, f"sample {n}: history"


# ============================================================================
# The cases (each groups several rule checks of the sections it names)
# ============================================================================

def _sub(tmp_path, name):
    d = tmp_path / name
    d.mkdir()
    return d


def test_pointers():
    _h_parse_pointer_tokens()
    _h_parse_pointer_errors()
    _h_format_pointer()
    _h_resolve_object_members_take_any_token()
    _h_resolve_array_index_rules()
    _h_resolve_through_scalars_and_identity()


def test_patch_list_limit_shape_and_members():
    _h_patch_must_be_a_list_and_respects_max_ops()
    _h_operation_shape_errors()
    _h_path_member_errors()
    _h_from_member_errors()
    _h_value_member_rules()


def test_patch_checks_first_atomicity_and_add():
    _h_every_operation_is_checked_before_any_is_applied()
    _h_inputs_are_never_modified_and_failure_is_atomic()
    _h_add_on_objects_and_root()
    _h_add_on_arrays()
    _h_add_needs_an_existing_container()


def test_patch_remove_replace_move_copy():
    _h_remove()
    _h_replace()
    _h_move_within_an_array_uses_the_document_after_removal()
    _h_move_same_path_and_into_child()
    _h_copy_is_deep()


def test_patch_test_and_json_equal():
    _h_test_operation_uses_json_equality()
    _h_json_equal()


def test_store_get_and_patch():
    _h_store_get_with_pointer()
    _h_store_patch_success_and_history()
    _h_store_patch_that_changes_nothing_still_bumps()
    _h_store_patch_dry_run()


def test_store_patch_errors_validation_and_limits():
    _h_store_patch_check_order_and_atomicity()
    _h_store_patch_validates_the_result()
    _h_max_ops_config()
    _h_package_exports()


def test_cli_get_and_patch(tmp_path):
    _h_cli_get(_sub(tmp_path, "g"))
    _h_cli_patch(_sub(tmp_path, "p"))
    _h_cli_patch_errors(_sub(tmp_path, "e"))


def test_conformance_pointers():
    _c_conformance_pointer_parse_and_format()
    _c_conformance_resolve()


def test_conformance_operations():
    _c_conformance_add()
    _c_conformance_remove_and_replace()
    _c_conformance_move()
    _c_conformance_copy_then_change()


def test_conformance_test_equality_and_checks():
    _c_conformance_test_operation()
    _c_conformance_json_equal()
    _c_conformance_operation_checks()


def test_conformance_sequences_and_store():
    _c_conformance_mixed_sequences_share_nothing()
    _c_conformance_store_patch()
