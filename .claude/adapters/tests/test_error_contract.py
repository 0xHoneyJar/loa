"""Sprint 1 Task 1.10 (bd-476) — error envelope contract tests.

Per SDD §3.3 contract-test requirements:
1. Every error code in the enum has at least one validating fixture.
2. Every fixture validates against error-v1.json via jsonschema.
3. CI gate on new-code-without-fixture — parametrized over the schema
   enum itself so adding a code without a fixture fails the test run.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Set

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from jsonschema import Draft7Validator, ValidationError

SCHEMA_DIR = Path(__file__).resolve().parent.parent / "loa_cheval" / "schemas"
FIXTURE_DIR = Path(__file__).resolve().parent / "fixtures" / "errors"

ERROR_SCHEMA_PATH = SCHEMA_DIR / "error-v1.json"


def _load_schema() -> dict:
    with open(ERROR_SCHEMA_PATH) as f:
        return json.load(f)


def _enum_codes() -> list[str]:
    schema = _load_schema()
    return schema["properties"]["error"]["properties"]["code"]["enum"]


def _load_fixture(code: str) -> dict:
    path = FIXTURE_DIR / f"{code}.json"
    with open(path) as f:
        return json.load(f)


# --- Schema self-validation ---


def test_schema_is_valid_draft7():
    schema = _load_schema()
    Draft7Validator.check_schema(schema)


def test_schema_has_exactly_sixteen_codes():
    """Sprint 1 AC pins the count; any future addition requires a new fixture
    and an explicit update here so the enum doesn't grow silently."""
    assert len(_enum_codes()) == 16


# --- Fixture coverage gate (the CI-relevant one) ---


@pytest.fixture(scope="module")
def validator() -> Draft7Validator:
    return Draft7Validator(_load_schema())


@pytest.mark.parametrize("code", _enum_codes())
def test_every_error_code_has_a_fixture(code: str):
    """SDD §3.3 item 1: every enum code has at least one fixture."""
    path = FIXTURE_DIR / f"{code}.json"
    assert path.exists(), f"missing fixture for {code} at {path}"


@pytest.mark.parametrize("code", _enum_codes())
def test_every_fixture_validates_against_schema(code: str, validator: Draft7Validator):
    """SDD §3.3 item 2: every fixture validates via jsonschema."""
    fixture = _load_fixture(code)
    validator.validate(fixture)  # raises on failure
    assert fixture["error"]["code"] == code, (
        f"fixture file {code}.json has mismatched code field "
        f"'{fixture['error']['code']}'"
    )


# --- Reject paths (negative tests) ---


def test_unknown_code_rejected(validator: Draft7Validator):
    bad = {"ok": False, "schema_version": "1.0", "error": {"code": "NOT_A_CODE", "message": "x", "retryable": False}}
    with pytest.raises(ValidationError):
        validator.validate(bad)


def test_missing_required_error_field_rejected(validator: Draft7Validator):
    # error.message is required
    bad = {"ok": False, "error": {"code": "INVALID_INPUT", "retryable": False}}
    with pytest.raises(ValidationError):
        validator.validate(bad)


def test_ok_true_rejected(validator: Draft7Validator):
    """ok must be const false for error envelope."""
    bad = {"ok": True, "error": {"code": "INVALID_INPUT", "message": "x", "retryable": False}}
    with pytest.raises(ValidationError):
        validator.validate(bad)


def test_chain_items_shape(validator: Draft7Validator):
    """PROVIDER_FAILOVER_EXHAUSTED fixture shape: chain is an array of
    {provider, code, attempt} objects."""
    fixture = _load_fixture("PROVIDER_FAILOVER_EXHAUSTED")
    chain = fixture["error"].get("chain", [])
    assert isinstance(chain, list)
    assert len(chain) >= 2, "failover fixture should include multiple hops"
    for hop in chain:
        assert "provider" in hop
        assert "code" in hop


# --- Fixture directory hygiene ---


def test_no_orphan_fixture_files():
    """Every fixture file maps to a live enum code (prevents fixture rot
    when a code is removed from the enum)."""
    enum = set(_enum_codes())
    orphans = []
    for path in FIXTURE_DIR.glob("*.json"):
        code = path.stem
        if code not in enum:
            orphans.append(code)
    assert orphans == [], f"orphan fixtures with no matching enum code: {orphans}"


# --- Round-trip: Python-side ChevalError → envelope → schema ---


def test_cheval_error_to_json_roundtrips_through_schema(validator: Draft7Validator):
    """Hand-built ChevalError.to_json() wrapped in an envelope must pass
    the schema — confirms the Python side produces on-contract envelopes."""
    from loa_cheval.types import InvalidInputError

    err = InvalidInputError("stdin missing 'prompt'")
    body = err.to_json()
    # ChevalError.to_json returns {error, code, message, retryable} — rewrap
    envelope = {
        "ok": False,
        "schema_version": "1.0",
        "error": {
            "code": body["code"],
            "message": body["message"],
            "retryable": body["retryable"],
        },
    }
    validator.validate(envelope)
