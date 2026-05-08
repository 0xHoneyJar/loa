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
