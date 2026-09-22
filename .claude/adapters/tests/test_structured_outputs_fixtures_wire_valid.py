"""Late Sprint 2 review (slice C, LOW): the fixture corpus's "enforced-valid"
label is pinned mechanically — every kf004 fixture the enforced branch must
accept validates against its dissent wire schema, every `neg-*` fixture does
not, and the accepted kf023 fixture validates against the reviewer wire schema.
Nothing else in the tree validated the corpus against the schemas it claims to
satisfy.
"""

from __future__ import annotations

import json
from pathlib import Path

import jsonschema
import pytest

REPO = Path(__file__).resolve().parents[3]
WIRE = REPO / ".claude" / "schemas" / "wire"
CORPUS = REPO / "tests" / "fixtures" / "structured-outputs"


def _fixtures(sub: str):
    return sorted((CORPUS / sub).glob("*.json"))


def _wire(name: str) -> dict:
    return json.loads((WIRE / name).read_text())


def _valid(schema: dict, payload: dict) -> bool:
    try:
        jsonschema.validate(payload, schema, cls=jsonschema.Draft202012Validator)
        return True
    except jsonschema.ValidationError:
        return False


@pytest.mark.parametrize("fixture", _fixtures("kf004"), ids=lambda p: p.stem)
def test_kf004_fixtures_match_their_wire_schema_verdict(fixture):
    doc = json.loads(fixture.read_text())
    expect = doc["_expect"]
    schema = _wire(f"dissent-{doc['_type']}.wire.json")
    try:
        payload = json.loads(doc["content"])
    except json.JSONDecodeError:
        assert expect["enforced"] == "malformed_response", f"{fixture.name}: unparseable content must be malformed on the enforced path"
        return
    if fixture.name.startswith("neg-"):
        assert not _valid(schema, payload), f"{fixture.name} is a negative fixture but passes the wire schema"
    elif expect["enforced"] in ("reviewed", "clean") and expect.get("enforced_rejected", 0) == 0:
        assert _valid(schema, payload), f"{fixture.name} is labelled enforced-valid but fails the wire schema"


def test_kf023_accepted_fixture_matches_the_reviewer_wire_schema():
    schema = _wire("flatline-reviewer.wire.json")
    seen = 0
    for fixture in _fixtures("kf023"):
        doc = json.loads(fixture.read_text())
        if doc["_expect"]["enforced"] != "accepted":
            continue
        seen += 1
        assert _valid(schema, json.loads(doc["content"])), fixture.name
    assert seen >= 1
