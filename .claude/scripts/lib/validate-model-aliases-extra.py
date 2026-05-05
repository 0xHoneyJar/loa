#!/usr/bin/env python3
"""validate-model-aliases-extra.py — cycle-099 Sprint 2A (T2.1).

Validates the `model_aliases_extra` block of an operator's `.loa.config.yaml`
against the canonical JSON Schema at
`.claude/data/trajectory-schemas/model-aliases-extra.schema.json` (DD-5 path).

This is a STANDALONE validator helper — it does NOT integrate with the
broader strict-mode loader (Sprint 2B+ scope). Operators and CI workflows
invoke this directly to catch malformed entries before runtime.

Usage:
    validate-model-aliases-extra.py [--config <path>] [--block <yaml-path>]
                                     [--json] [--quiet]

    --config <path>    Path to .loa.config.yaml (default: $PROJECT_ROOT/.loa.config.yaml)
    --block <path>     YAML jq-path to the model_aliases_extra block
                       (default: ".model_aliases_extra")
    --json             Emit machine-readable JSON output
    --quiet            Exit-code only; suppress stdout

Exit codes:
    0    valid (or `model_aliases_extra` absent — operator hasn't configured it)
    78   validation failed (EX_CONFIG)
    64   usage / IO error (EX_USAGE)

Schema reference: .claude/data/trajectory-schemas/model-aliases-extra.schema.json
SDD reference: cycle-099-model-registry §3.2 (DD-2 + DD-5 resolution)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

import jsonschema
import yaml

EXIT_VALID = 0
EXIT_INVALID = 78
EXIT_USAGE = 64


def _project_root() -> Path:
    """Walk upward from CWD looking for the .claude/ directory marker.

    Mirrors the cycle-099 PROJECT_ROOT resolution pattern used across other
    sprint scripts. Falls back to CWD if no marker found.
    """
    cwd = Path.cwd().resolve()
    for parent in [cwd, *cwd.parents]:
        if (parent / ".claude").is_dir():
            return parent
    return cwd


def _default_schema_path() -> Path:
    return _project_root() / ".claude" / "data" / "trajectory-schemas" / "model-aliases-extra.schema.json"


def _default_config_path() -> Path:
    return _project_root() / ".loa.config.yaml"


def _load_schema(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        schema = json.load(f)
    # Defense-in-depth: assert schema itself is well-formed Draft 2020-12.
    jsonschema.Draft202012Validator.check_schema(schema)
    return schema


def _load_config(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(f"config file not found: {path}")
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def _extract_block(config: dict[str, Any], block_path: str) -> Any:
    """Extract the model_aliases_extra block from the config.

    block_path is a dotted path (yaml-jq style). For Sprint 2A the only
    supported path is `.model_aliases_extra` — top-level. Future Sprint 2
    integrations may pass a different path if the loader nests the block
    under a parent key.
    """
    # Strip leading dot if present (jq-style).
    path = block_path.lstrip(".")
    if not path:
        return config
    parts = path.split(".")
    cursor: Any = config
    for part in parts:
        if not isinstance(cursor, dict):
            return None
        cursor = cursor.get(part)
        if cursor is None:
            return None
    return cursor


def _format_validation_errors(errors: list[jsonschema.ValidationError]) -> list[dict[str, Any]]:
    """Convert jsonschema ValidationErrors to a stable JSON-friendly shape."""
    out = []
    for err in errors:
        path_str = "/".join(str(p) for p in err.absolute_path) or "<root>"
        out.append({
            "path": path_str,
            "message": err.message,
            "validator": err.validator,
            "validator_value": err.validator_value if isinstance(err.validator_value, (str, int, float, bool, type(None))) else str(err.validator_value),
        })
    return out


def validate(
    config: dict[str, Any],
    schema: dict[str, Any],
    block_path: str = ".model_aliases_extra",
) -> tuple[bool, list[dict[str, Any]]]:
    """Validate a config's model_aliases_extra block against the schema.

    Returns (is_valid, errors). When the block is absent, returns
    (True, []) — operator hasn't opted in to the extension surface, which
    is the default state.
    """
    block = _extract_block(config, block_path)
    if block is None:
        return True, []
    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(block), key=lambda e: e.absolute_path)
    return (len(errors) == 0), _format_validation_errors(errors)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="validate-model-aliases-extra",
        description=__doc__.split("\n\n")[0],
    )
    parser.add_argument("--config", help="Path to .loa.config.yaml")
    parser.add_argument(
        "--block",
        default=".model_aliases_extra",
        help="YAML path to the model_aliases_extra block (default: .model_aliases_extra)",
    )
    parser.add_argument("--schema", help="Override schema path (default: canonical)")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    parser.add_argument("--quiet", action="store_true", help="Suppress stdout")
    args = parser.parse_args(argv)

    config_path = Path(args.config) if args.config else _default_config_path()
    schema_path = Path(args.schema) if args.schema else _default_schema_path()

    try:
        schema = _load_schema(schema_path)
    except FileNotFoundError:
        print(f"validate-model-aliases-extra: schema file not found: {schema_path}", file=sys.stderr)
        return EXIT_USAGE
    except (json.JSONDecodeError, jsonschema.SchemaError) as exc:
        print(f"validate-model-aliases-extra: schema malformed: {exc}", file=sys.stderr)
        return EXIT_USAGE

    if not config_path.is_file():
        # Operator has no .loa.config.yaml — vacuous success (no
        # model_aliases_extra to validate).
        if not args.quiet:
            payload = {"valid": True, "block_present": False, "config_path": str(config_path)}
            if args.json:
                print(json.dumps(payload, sort_keys=True, separators=(",", ":")))
            else:
                print(f"OK — no config at {config_path} (no model_aliases_extra to validate)")
        return EXIT_VALID

    try:
        config = _load_config(config_path)
    except yaml.YAMLError as exc:
        print(f"validate-model-aliases-extra: YAML parse failed for {config_path}: {exc}", file=sys.stderr)
        return EXIT_USAGE

    valid, errors = validate(config, schema, args.block)

    block = _extract_block(config, args.block)
    if not args.quiet:
        payload = {
            "valid": valid,
            "block_present": block is not None,
            "config_path": str(config_path),
            "schema_id": schema.get("$id", ""),
            "errors": errors,
        }
        if args.json:
            print(json.dumps(payload, sort_keys=True, separators=(",", ":")))
        else:
            if valid:
                if block is None:
                    print(f"OK — no `model_aliases_extra` block in {config_path}")
                else:
                    entry_count = len(block.get("entries", [])) if isinstance(block, dict) else 0
                    print(f"OK — model_aliases_extra valid ({entry_count} entries)")
            else:
                print(f"[MODEL-ALIASES-EXTRA-INVALID] schema validation failed:", file=sys.stderr)
                for err in errors:
                    print(f"  - {err['path']}: {err['message']}", file=sys.stderr)

    return EXIT_VALID if valid else EXIT_INVALID


if __name__ == "__main__":
    sys.exit(main())
