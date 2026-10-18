import pytest

import patchwork
from patchwork import PathError, PointerError

DOC = {"foo": ["bar", "baz"], "": 0, "a/b": 1, "c%d": 2, "e^f": 3, "g|h": 4, "i\\j": 5, "k\"l": 6, " ": 7, "m~n": 8}


@pytest.mark.parametrize("pointer,want", [
    ("", DOC), ("/foo", ["bar", "baz"]), ("/foo/0", "bar"), ("/", 0), ("/a~1b", 1), ("/c%d", 2),
    ("/e^f", 3), ("/g|h", 4), ("/i\\j", 5), ("/k\"l", 6), ("/ ", 7), ("/m~0n", 8),
])
def test_rfc6901_examples(pointer, want):
    assert patchwork.resolve(DOC, pointer) == want


def test_tokens_round_trip():
    assert patchwork.parse_pointer("/a~1b/~0/~01") == ["a/b", "~", "~1"]
    assert patchwork.format_pointer(["a/b", "~", "~1"]) == "/a~1b/~0/~01"


@pytest.mark.parametrize("text,message", [
    ("a", "invalid pointer: 'a'"),
    ("/a~", "invalid escape in pointer: '/a~'"),
    ("/~2", "invalid escape in pointer: '/~2'"),
    (5, "pointer must be a string: 5"),
])
def test_bad_pointers(text, message):
    with pytest.raises(PointerError) as info:
        patchwork.parse_pointer(text)
    assert str(info.value) == message


@pytest.mark.parametrize("pointer,message", [
    ("/nope", "path not found: '/nope'"),
    ("/foo/2", "index 2 out of range in '/foo/2'"),
    ("/foo/01", "invalid array index '01' in '/foo/01'"),
    ("/foo/-", "index '-' is past the end: '/foo/-'"),
    ("/a~1b/x", "cannot descend into a scalar at '/a~1b/x'"),
])
def test_resolve_errors(pointer, message):
    with pytest.raises(PathError) as info:
        patchwork.resolve(DOC, pointer)
    assert str(info.value) == message


def test_json_equal():
    assert patchwork.json_equal({"a": [1, 2.0]}, {"a": [1.0, 2]})
    assert not patchwork.json_equal(True, 1)
    assert not patchwork.json_equal([1, 2], [2, 1])
    assert not patchwork.json_equal(None, 0)


def test_list_pointers_in_document_order():
    doc = {"b": [1, {"x/y": None}], "a": "s"}
    assert patchwork.list_pointers(doc) == ["", "/b", "/b/0", "/b/1", "/b/1/x~1y", "/a"]
    assert patchwork.list_pointers(3) == [""]


def test_type_counts():
    assert patchwork.type_counts({"a": [1, 2.5, True, None, "s"], "b": {}}) == {
        "object": 2, "array": 1, "string": 1, "number": 2, "boolean": 1, "null": 1}
