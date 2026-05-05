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
import re
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


_BLOCK_PATH_RE = re.compile(r"^\.?[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$")


def _extract_block(config: dict[str, Any], block_path: str) -> Any:
    """Extract the model_aliases_extra block from the config.

    block_path is a dotted path (yaml-jq style). For Sprint 2A the only
    supported path is `.model_aliases_extra` — top-level. Future Sprint 2
    integrations may pass a different path if the loader nests the block
    under a parent key.

    Path syntax (gp M2 fix — formerly silently swallowed malformed paths):
      Optional leading dot, then one or more identifier segments separated
      by single dots. Identifiers are Python-shaped: letter or underscore
      followed by letters/digits/underscores. Empty paths, multiple leading
      dots, trailing dots, embedded double-dots all REJECTED with ValueError.
    """
    if not isinstance(block_path, str):
        raise ValueError(f"--block must be a string; got {type(block_path).__name__}")
    if not _BLOCK_PATH_RE.fullmatch(block_path):
        raise ValueError(
            f"--block path {block_path!r} is malformed; expected `.field` or "
            "`.parent.child` with identifier segments [A-Za-z_][A-Za-z0-9_]*"
        )
    path = block_path.lstrip(".")
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


def _load_framework_default_ids(framework_yaml: Path | None = None) -> set[str]:
    """cypherpunk H3 / IMP-004: load framework-default model IDs so we can
    reject `model_aliases_extra` entries that collide with framework-shipped
    IDs. Per SDD §3.3: `model_aliases_extra` ADDS new IDs (entries collide
    with defaults → reject); `model_aliases_override` MODIFIES existing.

    Returns the set of `id` keys under `providers.<p>.models.<id>` plus the
    keys of the top-level `aliases:` map. When the framework YAML cannot be
    located (test fixtures, --schema override, etc.), returns an empty set
    and skips the collision check (logged via the caller's error list, not
    via stderr).
    """
    path = framework_yaml or (_project_root() / ".claude" / "defaults" / "model-config.yaml")
    if not path.is_file():
        return set()
    try:
        with path.open("r", encoding="utf-8") as f:
            doc = yaml.safe_load(f) or {}
    except (yaml.YAMLError, OSError):
        return set()
    ids: set[str] = set()
    providers = doc.get("providers", {})
    if isinstance(providers, dict):
        for _provider, p_def in providers.items():
            if not isinstance(p_def, dict):
                continue
            models = p_def.get("models", {})
            if isinstance(models, dict):
                ids.update(str(k) for k in models.keys())
    aliases = doc.get("aliases", {})
    if isinstance(aliases, dict):
        ids.update(str(k) for k in aliases.keys())
    return ids


def _check_collisions(block: Any, framework_ids: set[str]) -> list[dict[str, Any]]:
    """cypherpunk H3 / IMP-004 — reject entries whose `id` collides with a
    framework-default ID. Operators wanting to MODIFY a framework default
    use `model_aliases_override` (separate top-level field — Sprint 2B
    scope); `model_aliases_extra` is for NEW IDs only.
    """
    if not isinstance(block, dict):
        return []
    entries = block.get("entries", [])
    if not isinstance(entries, list):
        return []
    errors = []
    for idx, entry in enumerate(entries):
        if not isinstance(entry, dict):
            continue
        entry_id = entry.get("id")
        if not isinstance(entry_id, str):
            continue
        if entry_id in framework_ids:
            errors.append({
                "path": f"entries/{idx}/id",
                "message": f"id {entry_id!r} collides with a framework-default model_id; "
                           f"use `model_aliases_override` to modify existing entries",
                "validator": "[MODEL-EXTRA-COLLIDES-WITH-DEFAULT]",
                "validator_value": "framework_default_collision_check",
            })
    return errors


def validate(
    config: dict[str, Any],
    schema: dict[str, Any],
    block_path: str = ".model_aliases_extra",
    framework_ids: set[str] | None = None,
) -> tuple[bool, list[dict[str, Any]], bool]:
    """Validate a config's model_aliases_extra block against the schema.

    Returns (is_valid, errors, block_present). When the block is absent,
    returns (True, [], False) — operator hasn't opted in to the extension
    surface (default state). When present, runs schema validation AND the
    cypherpunk H3 collision check against `framework_ids` if provided.

    gp M3 fix: returning `block_present` lets Sprint 2B's loader skip
    re-extracting the block. (Previously Sprint 2B would have to call
    _extract_block separately to distinguish vacuous-success from
    meaningful-success.)
    """
    block = _extract_block(config, block_path)
    if block is None:
        return True, [], False
    validator = jsonschema.Draft202012Validator(schema)
    schema_errors = sorted(validator.iter_errors(block), key=lambda e: e.absolute_path)
    errors = _format_validation_errors(schema_errors)
    if framework_ids is not None:
        errors.extend(_check_collisions(block, framework_ids))
    return (len(errors) == 0), errors, True


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
    parser.add_argument(
        "--framework-defaults",
        help="Override framework defaults yaml path (default: .claude/defaults/model-config.yaml). "
             "When set, entries colliding with framework default IDs are rejected per SDD §3.3.",
    )
    parser.add_argument(
        "--no-collision-check",
        action="store_true",
        help="Skip the framework-defaults collision check (cypherpunk H3 / IMP-004). "
             "Default OFF — operators should NOT use this; provided only for Sprint 2B integration tests.",
    )
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

    framework_ids: set[str] | None = None
    if not args.no_collision_check:
        fw_path = Path(args.framework_defaults) if args.framework_defaults else None
        framework_ids = _load_framework_default_ids(fw_path)

    try:
        valid, errors, block_present = validate(config, schema, args.block, framework_ids)
    except ValueError as exc:
        print(f"validate-model-aliases-extra: {exc}", file=sys.stderr)
        return EXIT_USAGE

    block = _extract_block(config, args.block) if block_present else None
    if not args.quiet:
        payload = {
            "valid": valid,
            "block_present": block_present,
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
