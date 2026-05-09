#!/usr/bin/env python3
"""validate-model-error.py — cycle-102 Sprint 1 (T1.1).

Validates a typed model-error JSON envelope against the canonical schema at
`.claude/data/trajectory-schemas/model-error.schema.json` (SDD section 4.1).

Standalone validator helper. Callers (cheval._error_json, the bash
model-adapter shim, audit-emit payloads, bats tests) invoke this directly to
catch malformed errors before they enter the audit chain or the
operator-visible header.

Usage:
    validate-model-error.py [--input <path> | --stdin] [--json] [--quiet]

    --input <path>     Path to a JSON file containing the error envelope.
    --stdin            Read the envelope JSON from stdin (default if no
                       --input given).
    --json             Emit machine-readable JSON output: {valid, errors[]}.
    --quiet            Exit-code only; suppress stdout.

Exit codes:
    0    valid
    78   validation failed (EX_CONFIG)
    64   usage / IO error (EX_USAGE)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import re

import jsonschema

EXIT_VALID = 0
EXIT_INVALID = 78
EXIT_USAGE = 64

# cycle-102 Sprint 1B T1B.2: Strict RFC 3339 date-time validation. The
# default jsonschema FORMAT_CHECKER does NOT include `date-time` unless
# rfc3339-validator is installed (which it isn't, by default). Register
# a strict checker inline so `format: "date-time"` is enforced consistently
# regardless of optional deps. Mirrors the inline regex in
# tests/unit/model-events-schemas.bats so test-time and production-time
# validation match.
_RFC3339_DATETIME_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"
)


def _build_format_checker() -> jsonschema.FormatChecker:
    fc = jsonschema.FormatChecker()

    @fc.checks("date-time", raises=ValueError)
    def _strict_rfc3339_datetime(value):  # pyright: ignore[reportUnusedFunction]
        if not isinstance(value, str):
            return True
        if not _RFC3339_DATETIME_RE.match(value):
            raise ValueError(f"value {value!r} is not a strict RFC 3339 date-time")
        return True

    return fc


_FORMAT_CHECKER = _build_format_checker()


def _project_root() -> Path:
    cwd = Path.cwd().resolve()
    for parent in [cwd, *cwd.parents]:
        if (parent / ".claude").is_dir():
            return parent
    return cwd


def _default_schema_path() -> Path:
    return (
        _project_root()
        / ".claude"
        / "data"
        / "trajectory-schemas"
        / "model-error.schema.json"
    )


def _load_schema(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        schema = json.load(f)
    jsonschema.Draft202012Validator.check_schema(schema)
    return schema


def _load_payload(args: argparse.Namespace) -> Any:
    if args.input:
        path = Path(args.input)
        if not path.is_file():
            raise FileNotFoundError(f"--input file not found: {path}")
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    raw = sys.stdin.read()
    if not raw.strip():
        raise ValueError("empty stdin — provide JSON via --input or pipe to stdin")
    return json.loads(raw)


def _format_error(err: jsonschema.ValidationError) -> dict[str, Any]:
    path = "/" + "/".join(str(p) for p in err.absolute_path)
    return {
        "path": path,
        "message": err.message,
        "validator": err.validator,
        "validator_value": err.validator_value,
    }


def _validate(payload: Any, schema: dict[str, Any]) -> list[dict[str, Any]]:
    # cycle-102 Sprint 1B T1B.2: pass format_checker so `format` keywords
    # (notably `ts_utc: format: date-time`) are enforced. Without this,
    # JSON Schema 2020-12 treats `format` as advisory and admits malformed
    # timestamps that bats tests rejected via inline regex — drift between
    # test-time and production-time validation. Source: BB iter-5 F2/FIND-004.
    # Use the module-level _FORMAT_CHECKER which registers a strict RFC 3339
    # date-time checker (the default FORMAT_CHECKER omits date-time unless
    # rfc3339-validator is installed).
    validator = jsonschema.Draft202012Validator(schema, format_checker=_FORMAT_CHECKER)
    return [_format_error(e) for e in validator.iter_errors(payload)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate a typed model-error envelope.",
        prog="validate-model-error",
    )
    src = parser.add_mutually_exclusive_group()
    src.add_argument("--input", help="path to JSON file containing the envelope")
    src.add_argument(
        "--stdin",
        action="store_true",
        help="read the envelope from stdin (default if no --input)",
    )
    parser.add_argument(
        "--schema",
        help=f"override schema path (default: {_default_schema_path()})",
    )
    parser.add_argument("--json", action="store_true", help="emit JSON result")
    parser.add_argument(
        "--quiet", action="store_true", help="exit-code only; suppress stdout"
    )
    args = parser.parse_args(argv)

    schema_path = Path(args.schema) if args.schema else _default_schema_path()

    try:
        schema = _load_schema(schema_path)
        payload = _load_payload(args)
    except (FileNotFoundError, json.JSONDecodeError, ValueError) as e:
        if not args.quiet:
            if args.json:
                print(json.dumps({"valid": False, "errors": [{"message": str(e)}]}))
            else:
                print(f"validate-model-error: {e}", file=sys.stderr)
        return EXIT_USAGE

    errors = _validate(payload, schema)

    if not args.quiet:
        if args.json:
            print(json.dumps({"valid": not errors, "errors": errors}, indent=2))
        elif errors:
            print(f"validate-model-error: invalid ({len(errors)} error(s))", file=sys.stderr)
            for err in errors:
                print(f"  {err['path']}: {err['message']}", file=sys.stderr)
        else:
            print("validate-model-error: valid")

    return EXIT_VALID if not errors else EXIT_INVALID


if __name__ == "__main__":
    sys.exit(main())
