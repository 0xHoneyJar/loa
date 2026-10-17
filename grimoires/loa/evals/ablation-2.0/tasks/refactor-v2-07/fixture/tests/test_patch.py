import pytest

import patchwork
from patchwork import OperationError, PatchError, PathError

TEST_FAILED = patchwork.TestFailed


def test_rfc6902_add_and_insert():
    assert patchwork.apply_patch({"foo": "bar"}, [{"op": "add", "path": "/baz", "value": "qux"}]) == {"foo": "bar", "baz": "qux"}
    assert patchwork.apply_patch({"foo": ["bar", "baz"]}, [{"op": "add", "path": "/foo/1", "value": "qux"}]) == {"foo": ["bar", "qux", "baz"]}
    assert patchwork.apply_patch([1], [{"op": "add", "path": "/-", "value": 2}, {"op": "add", "path": "/2", "value": 3}]) == [1, 2, 3]


def test_rfc6902_remove_replace():
    doc = {"baz": "qux", "foo": "bar"}
    assert patchwork.apply_patch(doc, [{"op": "remove", "path": "/baz"}]) == {"foo": "bar"}
    assert patchwork.apply_patch(doc, [{"op": "replace", "path": "/baz", "value": "boo"}]) == {"baz": "boo", "foo": "bar"}


def test_rfc6902_move_and_copy():
    doc = {"foo": {"bar": "baz", "waldo": "fred"}, "qux": {"corge": "grault"}}
    want = {"foo": {"bar": "baz"}, "qux": {"corge": "grault", "thud": "fred"}}
    assert patchwork.apply_patch(doc, [{"op": "move", "from": "/foo/waldo", "path": "/qux/thud"}]) == want
    assert patchwork.apply_patch([1, 2, 3, 4], [{"op": "move", "from": "/1", "path": "/3"}]) == [1, 3, 4, 2]
    assert patchwork.apply_patch({"a": [1]}, [{"op": "copy", "from": "/a", "path": "/b"}]) == {"a": [1], "b": [1]}


def test_whole_document_operations():
    assert patchwork.apply_patch({"a": 1}, [{"op": "replace", "path": "", "value": [9]}]) == [9]
    assert patchwork.apply_patch({"a": 1}, [{"op": "add", "path": "", "value": 3}]) == 3
    with pytest.raises(PathError, match=r"^operation 0: cannot remove the root$"):
        patchwork.apply_patch({"a": 1}, [{"op": "remove", "path": ""}])


def test_test_operation():
    doc = {"baz": "qux", "foo": ["a", 2, "c"]}
    ok = [{"op": "test", "path": "/baz", "value": "qux"}, {"op": "test", "path": "/foo/1", "value": 2.0}]
    assert patchwork.apply_patch(doc, ok) == doc
    with pytest.raises(TEST_FAILED, match=r"^operation 1: test failed at '/baz'$"):
        patchwork.apply_patch(doc, [{"op": "test", "path": "/foo/1", "value": 2}, {"op": "test", "path": "/baz", "value": "bar"}])
    with pytest.raises(TEST_FAILED):
        patchwork.apply_patch({"t": True}, [{"op": "test", "path": "/t", "value": 1}])


def test_patches_are_atomic_and_never_mutate():
    doc = {"a": [1, 2]}
    with pytest.raises(PathError, match=r"^operation 1: path not found: '/b/c'$"):
        patchwork.apply_patch(doc, [{"op": "add", "path": "/a/-", "value": 3}, {"op": "add", "path": "/b/c", "value": 1}])
    assert doc == {"a": [1, 2]}


def test_values_are_copied_in():
    value = {"x": [1]}
    out = patchwork.apply_patch({}, [{"op": "add", "path": "/v", "value": value}])
    out["v"]["x"].append(2)
    assert value == {"x": [1]}


@pytest.mark.parametrize("patch,message", [
    ({"op": "add"}, "patch must be a list"),
    (["add"], "operation 0: not an object"),
    ([{"path": "/a"}], "operation 0: missing 'op'"),
    ([{"op": "merge", "path": "/a"}], "operation 0: unknown op 'merge'"),
    ([{"op": "add", "path": "/a", "value": 1}, {"op": "add", "value": 1}], "operation 1: missing 'path'"),
    ([{"op": "add", "path": "/a"}], "operation 0: missing 'value'"),
    ([{"op": "copy", "path": "/a"}], "operation 0: missing 'from'"),
    ([{"op": "remove", "path": 3}], "operation 0: 'path' must be a string"),
    ([{"op": "move", "from": "/a", "path": "/a/b"}], "operation 0: cannot move a value into itself"),
])
def test_malformed_operations(patch, message):
    with pytest.raises(OperationError) as info:
        patchwork.apply_patch({"a": {}}, patch)
    assert str(info.value) == message


def test_all_operations_are_checked_before_any_applies():
    with pytest.raises(OperationError, match=r"^operation 1: unknown op 'x'$"):
        patchwork.apply_patch({}, [{"op": "remove", "path": "/missing"}, {"op": "x", "path": ""}])


def test_errors_share_a_base():
    for cls in (OperationError, PathError, TEST_FAILED, patchwork.PointerError):
        assert issubclass(cls, PatchError) and issubclass(cls, ValueError)


def test_diff():
    a = {"a": 1, "b": [1, 2], "c": {"d": True}}
    b = {"a": 1.0, "b": [1, 3], "c": {"e": None}, "z": 0}
    assert patchwork.diff(a, b) == [
        {"op": "replace", "path": "/b/1", "value": 3},
        {"op": "remove", "path": "/c/d"},
        {"op": "add", "path": "/c/e", "value": None},
        {"op": "add", "path": "/z", "value": 0},
    ]
    assert patchwork.diff([1], [1, 2]) == [{"op": "replace", "path": "", "value": [1, 2]}]
    assert patchwork.apply_patch(a, patchwork.diff(a, b)) == b


def test_explain():
    patch = [{"op": "add", "path": "/a", "value": {"y": 1, "x": [True]}}, {"op": "move", "from": "", "path": ""}, {"op": "remove", "path": "/a"}]
    assert patchwork.explain(patch) == '1. add /a = {"x":[true],"y":1}\n2. move (root) from (root)\n3. remove /a'
    assert patchwork.explain([]) == "(empty patch)"
