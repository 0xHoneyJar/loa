import pytest

from docstore import Config, Conflict, ExportError, InvalidId, NotFound, Store, ValidationError
from docstore.canon import canonical, digest
from docstore.config import parse_config
from docstore.errors import ConfigError
from docstore.export import export_bundle, import_bundle
from docstore.query import find, select
from docstore.validate import validate_document


def test_create_get_and_revision():
    s = Store()
    assert s.create("a", {"x": [1, 2]}) == 1
    assert s.get("a") == {"x": [1, 2]}
    assert s.revision("a") == 1


def test_get_returns_a_copy():
    s = Store()
    doc = {"x": [1]}
    s.create("a", doc)
    doc["x"].append(2)
    got = s.get("a")
    got["x"].append(3)
    assert s.get("a") == {"x": [1]}


def test_put_bumps_revision_and_checks_expected_rev():
    s = Store()
    s.create("a", {})
    assert s.put("a", {"v": 1}) == 2
    with pytest.raises(Conflict) as exc:
        s.put("a", {"v": 2}, expected_rev=1)
    assert str(exc.value) == "revision mismatch for 'a': expected 1, found 2"
    assert s.put("a", {"v": 2}, expected_rev=2) == 3


def test_create_twice_conflicts_and_missing_is_not_found():
    s = Store()
    s.create("a", {})
    with pytest.raises(Conflict):
        s.create("a", {})
    with pytest.raises(NotFound) as exc:
        s.get("b")
    assert str(exc.value) == "no document 'b'"


def test_invalid_ids():
    s = Store()
    for bad in ["", "A", "-a", "a" * 41, "a/b"]:
        with pytest.raises(InvalidId):
            s.create(bad, {})


def test_validation_rules():
    with pytest.raises(ValidationError, match="document root must be an object"):
        validate_document([1])
    with pytest.raises(ValidationError, match=r"non-finite number at \$\.a\[1\]"):
        validate_document({"a": [1, float("nan")]})
    with pytest.raises(ValidationError, match="nesting deeper than 2 at"):
        validate_document({"a": {"b": {}}}, max_depth=2)
    with pytest.raises(ValidationError, match=r"unsupported value of type tuple at \$\.t"):
        validate_document({"t": (1,)})
    with pytest.raises(ValidationError, match="limit 5"):
        validate_document({"abc": 1}, max_bytes=5)
    assert validate_document({"a": [True, None, 1.5, "s"]}) == len('{"a":[true,null,1.5,"s"]}')


def test_history_lines():
    s = Store()
    s.create("a", {"v": 1})
    s.put("a", {"v": 2})
    s.delete("a")
    lines = s.history.lines()
    assert lines[0] == f"1\ta\tcreate\t1\t{digest({'v': 1})}\t-"
    assert lines[1] == f"2\ta\tput\t2\t{digest({'v': 2})}\t-"
    assert lines[2] == "3\ta\tdelete\t2\t-\t-"
    assert [e.action for e in s.history.entries("a")] == ["create", "put", "delete"]


def test_failed_put_leaves_no_trace():
    s = Store()
    s.create("a", {"v": 1})
    with pytest.raises(ValidationError):
        s.put("a", {"v": float("inf")})
    assert s.revision("a") == 1 and len(s.history.lines()) == 1


def test_canonical_form():
    assert canonical({"b": 1, "a": [True, None, "é"]}) == '{"a":[true,null,"é"],"b":1}'
    assert len(digest({})) == 12


def test_select_and_find():
    s = Store()
    s.create("a", {"tags": ["x", "y"], "n": 1})
    s.create("b", {"tags": ["y"], "n": True})
    assert select(s.get("a"), "tags.1") == "y"
    assert select(s.get("a"), "") == s.get("a")
    with pytest.raises(NotFound):
        select(s.get("a"), "tags.2")
    assert find(s, "tags.0", "y") == ["b"]
    assert find(s, "n", 1) == ["a"]


def test_config_parsing():
    c = parse_config("# c\nmax_depth = 4\n\nhistory_file = h.log\n")
    assert c == Config(max_depth=4, history_file="h.log")
    with pytest.raises(ConfigError, match="c:1: unknown key 'nope'"):
        parse_config("nope = 1", "c")
    with pytest.raises(ConfigError, match="max_bytes must be a positive integer"):
        parse_config("max_bytes = 0")
    with pytest.raises(ConfigError, match="duplicate key"):
        parse_config("max_depth = 1\nmax_depth = 2")


def test_bundle_round_trip():
    s = Store()
    s.create("b", {"v": 2})
    s.create("a", {"v": 1})
    s.put("a", {"v": 3})
    text = export_bundle(s)
    t = Store()
    assert import_bundle(t, text) == 2
    assert t.revision("a") == 2 and t.get("a") == {"v": 3}
    with pytest.raises(ExportError, match="ids already present: a, b"):
        import_bundle(t, text)
    assert import_bundle(t, text, replace=True) == 2
    assert t.history.entries("a")[0].detail == "bundle"


def test_bundle_errors():
    t = Store()
    with pytest.raises(ExportError, match="not a docstore-bundle/1 bundle"):
        import_bundle(t, "{}")
    with pytest.raises(ExportError, match="entry 0 has an invalid rev"):
        import_bundle(t, '{"format":"docstore-bundle/1","docs":[{"id":"a","rev":true,"doc":{}}]}')
    with pytest.raises(ExportError, match="invalid JSON"):
        import_bundle(t, "{")
