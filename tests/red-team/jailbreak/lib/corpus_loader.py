"""Cycle-100 T1.2 — Python corpus loader.

Mirrors corpus_loader.sh; same iteration order (LC_ALL=C ASC by vector_id),
same comment-stripping rule (^\\s*#), same failure modes.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Optional

try:
    from jsonschema import Draft202012Validator
except ImportError as exc:  # pragma: no cover - environment must provide
    raise SystemExit(
        "python jsonschema 4.x not available; install via "
        "`pip install --no-deps jsonschema==4.*`"
    ) from exc


_LIB_DIR = Path(__file__).resolve().parent
_TREE_DIR = _LIB_DIR.parent
_REPO_ROOT = _LIB_DIR.parent.parent.parent.parent


def _test_mode_active() -> bool:
    """Cycle-098 L4/L6/L7 dual-condition pattern: env override honored
    only when LOA_JAILBREAK_TEST_MODE=1 AND a bats / pytest marker is set."""
    if os.environ.get("LOA_JAILBREAK_TEST_MODE") != "1":
        return False
    return bool(
        os.environ.get("BATS_TEST_FILENAME")
        or os.environ.get("BATS_VERSION")
        or os.environ.get("PYTEST_CURRENT_TEST")
    )


def _resolve_override(var_name: str, default_value: str) -> str:
    override = os.environ.get(var_name, "")
    if not override:
        return default_value
    if _test_mode_active():
        return override
    import sys
    sys.stderr.write(
        f"corpus_loader: WARNING: {var_name} ignored outside test mode "
        f"(set LOA_JAILBREAK_TEST_MODE=1 + bats/pytest marker)\n"
    )
    return default_value


SCHEMA_PATH = Path(
    _resolve_override(
        "LOA_JAILBREAK_VECTOR_SCHEMA",
        str(_REPO_ROOT / ".claude/data/trajectory-schemas/jailbreak-vector.schema.json"),
    )
)
CORPUS_DIR = Path(
    _resolve_override(
        "LOA_JAILBREAK_CORPUS_DIR",
        str(_TREE_DIR / "corpus"),
    )
)

_COMMENT_RE = re.compile(r"^\s*(#|$)")


@dataclass(frozen=True)
class Vector:
    """Frozen dataclass mirroring vector schema fields."""

    vector_id: str
    category: str
    title: str
    defense_layer: str
    payload_construction: str
    expected_outcome: str
    source_citation: str
    severity: str
    status: str
    suppression_reason: Optional[str] = None
    superseded_by: Optional[str] = None
    expected_marker: Optional[str] = None
    expected_absent_marker: Optional[str] = None
    notes: Optional[str] = None

    @classmethod
    def from_dict(cls, data: dict) -> "Vector":
        kwargs = {k: data.get(k) for k in cls.__dataclass_fields__}
        return cls(**kwargs)


def _load_schema():
    with SCHEMA_PATH.open() as f:
        return json.load(f)


def _iter_corpus_lines(corpus_dir: Path) -> Iterator[tuple[Path, int, str]]:
    if not corpus_dir.is_dir():
        return
    for path in sorted(corpus_dir.glob("*.jsonl"), key=lambda p: p.name):
        with path.open() as f:
            for lineno, raw in enumerate(f, start=1):
                if _COMMENT_RE.match(raw):
                    continue
                stripped = raw.rstrip("\n")
                if not stripped.strip():
                    continue
                yield path, lineno, stripped


def validate_all(corpus_dir: Optional[Path] = None) -> list[str]:
    """Validate every corpus JSONL line; return list of error strings.

    Empty list = valid. Each error: "<file>:<line>:<vector_id>:<message>".
    Duplicate vector_ids across the corpus are reported.
    """
    corpus_dir = corpus_dir or CORPUS_DIR
    schema = _load_schema()
    validator = Draft202012Validator(schema)
    errors: list[str] = []
    seen: dict[str, str] = {}

    for path, lineno, raw in _iter_corpus_lines(corpus_dir):
        try:
            instance = json.loads(raw)
        except json.JSONDecodeError as e:
            errors.append(f"{path}:{lineno}:?:JSON parse error: {e}")
            continue
        if not isinstance(instance, dict):
            errors.append(f"{path}:{lineno}:?:not a JSON object")
            continue
        vid = instance.get("vector_id", "?")
        line_errors = list(validator.iter_errors(instance))
        if line_errors:
            for err in line_errors:
                pointer = "/".join(str(p) for p in err.path) or "<root>"
                errors.append(f"{path}:{lineno}:{vid}:{pointer}: {err.message}")
            continue
        if vid in seen:
            errors.append(f"{path}:{lineno}:{vid}:duplicate vector_id (also at {seen[vid]})")
        else:
            seen[vid] = f"{path}:{lineno}"
    return errors


def iter_active(category: str = "", corpus_dir: Optional[Path] = None) -> Iterator[Vector]:
    """Yield active vectors filtered by category (empty = all).

    Sort order matches bash loader: ASC by vector_id under byte-order
    (LC_ALL=C). Validation is eager: any malformed line raises ValueError
    listing all errors.
    """
    corpus_dir = corpus_dir or CORPUS_DIR
    errors = validate_all(corpus_dir)
    if errors:
        raise ValueError("corpus_loader: invalid corpus; first error: " + errors[0])
    schema = _load_schema()
    validator = Draft202012Validator(schema)
    rows: list[Vector] = []
    for _, _, raw in _iter_corpus_lines(corpus_dir):
        instance = json.loads(raw)
        # Re-validate; cheap and explicit (defense in depth).
        for _e in validator.iter_errors(instance):  # pragma: no cover
            raise ValueError(f"validation regressed for {instance.get('vector_id')}")
        if instance.get("status") != "active":
            continue
        if category and instance.get("category") != category:
            continue
        rows.append(Vector.from_dict(instance))
    rows.sort(key=lambda v: v.vector_id)
    yield from rows


def get_field(vector_id: str, field: str, corpus_dir: Optional[Path] = None) -> Optional[str]:
    """Return field value for a vector, or None if vector_id unknown."""
    corpus_dir = corpus_dir or CORPUS_DIR
    for _, _, raw in _iter_corpus_lines(corpus_dir):
        instance = json.loads(raw)
        if instance.get("vector_id") == vector_id:
            return instance.get(field)
    return None


def count_by_status(corpus_dir: Optional[Path] = None) -> dict[str, int]:
    """Return {active, superseded, suppressed} count dict."""
    corpus_dir = corpus_dir or CORPUS_DIR
    counts = {"active": 0, "superseded": 0, "suppressed": 0}
    for _, _, raw in _iter_corpus_lines(corpus_dir):
        try:
            instance = json.loads(raw)
        except json.JSONDecodeError:
            continue
        s = instance.get("status")
        if s in counts:
            counts[s] += 1
    return counts


_REPLAY_DIR = Path(
    _resolve_override(
        "LOA_JAILBREAK_REPLAY_DIR",
        str(_TREE_DIR / "fixtures" / "replay"),
    )
)

# Sentinel pattern in replay JSON `content` strings. Replaced at test time
# by `substitute_runtime_payloads` with the output of the corresponding
# fixture function. Anchored placeholder to avoid accidental collision
# with legitimate prose containing the substring "FIXTURE:".
#
# Cypherpunk M5 closure (Sprint 2 T2.7): trailing whitespace is tolerated.
# /review-sprint NEW-B1 closure (cross-validated by Opus DISS-001): leading
# whitespace is also tolerated. Both ends are permissive because fixture
# authors routinely have leading or trailing `\n` in JSON content strings.
# Without symmetric tolerance, `re.fullmatch("...", "  __FIXTURE..._")`
# silently fails the placeholder match, the placeholder string passes
# through unchanged, the SUT sees a literal `__FIXTURE:..._` token (no
# trigger ever runs), and `_count_redactions` stays at 0 — vacuously-green.
_PLACEHOLDER_RE = re.compile(r"\s*__FIXTURE:(_make_evil_body_[a-z0-9_]+)__\s*")

# Cypherpunk M1 closure: vector_id shape pin matching the schema regex.
# Without this, a test author calling load_replay_fixture(vector_id=...)
# directly (e.g., via _FakeVector) could pass `../../../etc/passwd` and
# read arbitrary `.json`-suffix files via pathlib.
_VECTOR_ID_RE = re.compile(r"^RT-[A-Z]{2,3}-\d{3,4}$")

# Cypherpunk M2 closure: fixture-module import allowlist mirrors the
# schema enum. importlib.import_module is otherwise unrestricted; a
# _FakeVector(category="os") would import the stdlib `os` module and
# attempt `getattr(os, fn_name)` — code-execution risk if a fixture
# function name happened to alias an `os` builtin (rare but real).
_FIXTURE_CATEGORY_ALLOWLIST = frozenset({
    "role_switch",
    "tool_call_exfiltration",
    "credential_leak",
    "markdown_indirect",
    "unicode_obfuscation",
    "encoded_payload",
    "multi_turn_conditioning",
})


class FixtureMissing(Exception):
    """Raised when a replay fixture references a fixture function that does
    not exist in fixtures/<category>.py. SDD §4.1.3 contract: runner-time
    defer (loader-time validation does NOT pre-import the fixtures, so
    fixture-name validity is not enforced by the schema)."""


class ReplayFixtureMissing(Exception):
    """Raised when fixtures/replay/<vector_id>.json is missing for a
    multi_turn_conditioning vector. Distinct error class so the harness
    can surface a precise diagnostic per SDD §4.4."""


def load_replay_fixture(
    vector_id: str, replay_dir: Optional[Path] = None
) -> dict:
    """Load fixtures/replay/<vector_id>.json as a dict.

    Validates minimum shape (turns array; each turn has role+content;
    optional expected_per_turn_redactions array).

    Raises ReplayFixtureMissing if the file is absent.
    Raises ValueError on malformed JSON or missing required fields.
    """
    if not _VECTOR_ID_RE.match(vector_id):
        raise ValueError(
            f"REPLAY-INVALID: vector_id shape {vector_id!r} does not match "
            f"^RT-[A-Z]{{2,3}}-\\d{{3,4}}$ (path-traversal defense)"
        )
    replay_dir = replay_dir or _REPLAY_DIR
    fp = replay_dir / f"{vector_id}.json"
    if not fp.is_file():
        raise ReplayFixtureMissing(
            f"REPLAY-MISSING: no replay fixture at {fp}"
        )
    try:
        with fp.open() as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise ValueError(f"REPLAY-INVALID: {fp}: {e}") from e
    if not isinstance(data, dict):
        raise ValueError(f"REPLAY-INVALID: {fp}: top-level not an object")
    turns = data.get("turns")
    if not isinstance(turns, list) or not turns:
        raise ValueError(
            f"REPLAY-INVALID: {fp}: 'turns' missing or not a non-empty list"
        )
    for i, turn in enumerate(turns):
        if not isinstance(turn, dict):
            raise ValueError(f"REPLAY-INVALID: {fp}: turn[{i}] not an object")
        if "role" not in turn or "content" not in turn:
            raise ValueError(
                f"REPLAY-INVALID: {fp}: turn[{i}] missing 'role' or 'content'"
            )
        if turn["role"] not in ("operator", "downstream"):
            raise ValueError(
                f"REPLAY-INVALID: {fp}: turn[{i}].role "
                f"must be operator|downstream"
            )
        if not isinstance(turn["content"], str):
            raise ValueError(
                f"REPLAY-INVALID: {fp}: turn[{i}].content must be string"
            )
    pt = data.get("expected_per_turn_redactions")
    if pt is not None:
        if not isinstance(pt, list) or not all(
            isinstance(x, int) and x >= 0 for x in pt
        ):
            raise ValueError(
                f"REPLAY-INVALID: {fp}: expected_per_turn_redactions "
                f"must be list of non-negative ints"
            )
        if len(pt) != len(turns):
            raise ValueError(
                f"REPLAY-INVALID: {fp}: expected_per_turn_redactions length "
                f"{len(pt)} != turns length {len(turns)}"
            )
    return data


def substitute_runtime_payloads(fixture: dict, vector: Vector) -> dict:
    """Walk fixture['turns'][*]['content']; replace placeholder strings of
    form `__FIXTURE:_make_evil_body_<id>__` with the output of the matching
    fixture function imported from fixtures/<vector.category>.py.

    Raises FixtureMissing if a placeholder names a function not present in
    the category's FIXTURES registry.

    Returns a NEW dict (does NOT mutate the input fixture).
    """
    import importlib

    # Deep-copy turns to avoid mutating caller state.
    out = dict(fixture)
    out["turns"] = [dict(t) for t in fixture["turns"]]

    # Cypherpunk M2 closure: enforce category allowlist before any import.
    # Schema-validated corpus rows always match the enum; _FakeVector and
    # bypassed-validation paths can not import attacker-controlled modules.
    if vector.category not in _FIXTURE_CATEGORY_ALLOWLIST:
        raise FixtureMissing(
            f"FIXTURE-CATEGORY-FORBIDDEN: category={vector.category!r} "
            f"not in allowlist {sorted(_FIXTURE_CATEGORY_ALLOWLIST)}"
        )
    # Lazy-import the fixture module for this vector's category.
    # Module name is the category (filename matches; sys.path injected
    # by conftest at /tests/red-team/jailbreak/fixtures/).
    fixtures_dir = _TREE_DIR / "fixtures"
    import sys
    if str(fixtures_dir) not in sys.path:
        sys.path.insert(0, str(fixtures_dir))
    try:
        mod = importlib.import_module(vector.category)
    except ModuleNotFoundError as e:
        raise FixtureMissing(
            f"FIXTURE-MODULE-MISSING: no fixtures module for "
            f"category={vector.category} ({e})"
        ) from e
    registry = getattr(mod, "FIXTURES", {})

    for i, turn in enumerate(out["turns"]):
        content = turn["content"]
        # Cypherpunk M5 closure: fullmatch with `\s*` allows trailing
        # whitespace (typical fixture-author convention) without making
        # the placeholder match mid-string. A stripped variant is checked
        # only after the prefix anchor confirms placeholder shape.
        m = _PLACEHOLDER_RE.fullmatch(content)
        if not m:
            continue
        fn_name = m.group(1)
        # Look up the function by NAME on the module (NOT in FIXTURES, which
        # is keyed by vector_id). Multi-turn replay fixtures often reference
        # auxiliary helpers (e.g., _make_evil_body_rt_mt_001_t2) that are
        # NOT primary vector fixtures and so are not in FIXTURES.
        fn = getattr(mod, fn_name, None)
        if fn is None or not callable(fn):
            # Defense-in-depth: also check FIXTURES registry by .__name__
            for _vid, candidate in registry.items():
                if getattr(candidate, "__name__", "") == fn_name:
                    fn = candidate
                    break
        if fn is None:
            raise FixtureMissing(
                f"FIXTURE-MISSING: function {fn_name} not in "
                f"fixtures/{vector.category}.py (turn {i})"
            )
        turn["content"] = fn()
    return out


if __name__ == "__main__":  # pragma: no cover - CLI for ad-hoc inspection
    import argparse, sys

    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("validate-all")
    iter_p = sub.add_parser("iter-active")
    iter_p.add_argument("--category", default="")
    field_p = sub.add_parser("get-field")
    field_p.add_argument("vector_id")
    field_p.add_argument("field")
    sub.add_parser("count")
    args = p.parse_args()

    if args.cmd == "validate-all":
        errs = validate_all()
        for e in errs:
            print(e, file=sys.stderr)
        sys.exit(1 if errs else 0)
    elif args.cmd == "iter-active":
        for v in iter_active(args.category):
            print(json.dumps(v.__dict__, sort_keys=True, ensure_ascii=False))
    elif args.cmd == "get-field":
        val = get_field(args.vector_id, args.field)
        if val is None:
            print(f"corpus_loader: vector_id not found: {args.vector_id}", file=sys.stderr)
            sys.exit(1)
        print(val)
    elif args.cmd == "count":
        c = count_by_status()
        print(f"active={c['active']}\tsuperseded={c['superseded']}\tsuppressed={c['suppressed']}")
