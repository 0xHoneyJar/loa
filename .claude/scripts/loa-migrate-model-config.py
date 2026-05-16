#!/usr/bin/env python3
"""loa migrate-model-config — operator-explicit v1 → v2 migration CLI.

cycle-099 Sprint 1E (T1.14). Implements SDD §3.1.1.1 contract:
  - Reads input YAML with ruamel.yaml (round-trip mode)
  - Detects schema_version (absent → v1; explicit 1/2/≥3)
  - Dispatches to pure migrate_v1_to_v2 (lib/model-config-migrate.py)
  - Validates output against the v2 JSON Schema
  - Reports field-level changes (text or JSON)
  - Exits 0 on success, 78 on validation failure or unsupported schema_version

Usage:
  loa-migrate-model-config.py INPUT.yaml -o OUTPUT.yaml
  loa-migrate-model-config.py INPUT.yaml -o OUT.yaml --model-permissions cycle-026.yaml
  loa-migrate-model-config.py INPUT.yaml -o OUT.yaml --report-format json
  loa-migrate-model-config.py INPUT.yaml -o OUT.yaml --dry-run

The CLI is non-destructive: it never overwrites the input file. Operators
should review the structured report and the diff between input and output
before adopting the v2 file as their authoritative config.

Limitation: in-line YAML comments and blank-line formatting are NOT preserved
across migration in this Sprint 1E shipment. The transformation is structural
(key order, nesting). Operators with heavily-commented configs should review
the v2 output and re-add comments. A future cycle may add a
--preserve-comments flag using ruamel's full round-trip mutation API.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from pathlib import Path
from typing import Any

EXIT_SUCCESS = 0
EXIT_VALIDATION_FAIL = 78  # EX_CONFIG (sysexits.h convention)
EXIT_USAGE = 64  # EX_USAGE

# Mode 0600: the migrated v2 file may carry merged trust_scopes from the
# cycle-026 model-permissions.yaml — operator-sensitive. Keep it owner-only
# regardless of the operator's umask.
_OUTPUT_FILE_MODE = 0o600


def _load_migrate_module():
    """Import the sibling lib/model-config-migrate.py via importlib.

    The module name has dashes (per cycle-099 file-naming convention), which
    makes plain `import` impossible — we use a spec loader instead.
    """
    here = Path(__file__).resolve().parent
    target = here / "lib" / "model-config-migrate.py"
    spec = importlib.util.spec_from_file_location("model_config_migrate", target)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {target}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_yaml(path: Path) -> Any:
    from ruamel.yaml import YAML

    yaml = YAML(typ="rt")
    with path.open("r") as f:
        return yaml.load(f)


def _dump_yaml(data: Any, path: Path) -> None:
    """Write `data` to `path` as YAML.

    Symlink-safe: refuses to write through an existing symlink (review
    remediation C-H2; prevents clobbering symlink targets like
    ~/.aws/credentials, sensitive configs, or git-tracked paths the operator
    forgot were symlinked). If the target exists as a regular file we
    overwrite via O_TRUNC; if it does not exist we create with mode 0600
    (owner-only — review remediation C-L1).
    """
    from ruamel.yaml import YAML

    if path.is_symlink():
        raise SymlinkRefusedError(
            f"output path {path} is a symlink; refusing to follow. "
            "Remove the symlink and re-run, or pick a different --output."
        )

    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW
    fd = os.open(path, flags, _OUTPUT_FILE_MODE)
    try:
        with os.fdopen(fd, "w") as f:
            yaml = YAML(typ="rt")
            yaml.indent(mapping=2, sequence=4, offset=2)
            yaml.dump(data, f)
    except BaseException:
        # If yaml.dump raised after fdopen took ownership, fdopen's close runs
        # via context-manager. If the os.open succeeded but fdopen didn't,
        # close manually.
        try:
            os.close(fd)
        except OSError:
            pass
        raise


class SymlinkRefusedError(OSError):
    """Raised when --output points at an existing symlink."""


def _to_plain_dict(data: Any) -> Any:
    """Convert ruamel CommentedMap/CommentedSeq → plain dict/list recursively.

    The pure migrate function operates on plain Python dicts; passing ruamel's
    round-trip types in directly works most of the time, but post-mutation
    serialization via `yaml.dump` on a ruamel-typed dict that has had keys
    inserted in arbitrary order can produce surprising output. Round-tripping
    through plain types simplifies the contract.
    """
    if isinstance(data, dict):
        return {k: _to_plain_dict(v) for k, v in data.items()}
    if isinstance(data, list):
        return [_to_plain_dict(v) for v in data]
    return data


def _validate_v2(
    data: dict[str, Any],
    schema_path: Path,
    *,
    error_code: str = "MIGRATION-PRODUCED-INVALID-V2",
) -> list[dict[str, Any]]:
    """Run jsonschema validation against the v2 schema. Returns list of error dicts.

    `error_code` lets the caller distinguish failures the migrator is
    responsible for (default `MIGRATION-PRODUCED-INVALID-V2`) from failures
    where the input was already v2 and didn't pass schema (operator handed
    us a corrupt v2 file → `CONFIG-V2-INVALID`). Review remediation G-M4.
    """
    import jsonschema

    with schema_path.open("r") as f:
        schema = json.load(f)
    validator = jsonschema.Draft202012Validator(schema)
    errors: list[dict[str, Any]] = []
    for err in validator.iter_errors(data):
        errors.append(
            {
                "code": error_code,
                "field": ".".join(str(p) for p in err.absolute_path) or "<root>",
                "detail": err.message,
            }
        )
    return errors


def _emit_text_report(report: list[dict[str, Any]]) -> str:
    if not report:
        # Review remediation G-M2: this branch is now reachable only when the
        # migrator returns an empty report — which our v1→v2 path no longer
        # does (it always emits at least the version_bump entry). Leaving the
        # message defensive in case future edits change that contract.
        return "(no changes — input may be malformed)\n"
    lines = []
    for entry in report:
        sev = entry.get("severity", "INFO")
        code = entry.get("code")
        prefix = f"[{sev}]"
        if code:
            prefix = f"[{sev}] [{code}]"
        lines.append(f"{prefix} {entry.get('detail', '')}")
    return "\n".join(lines) + "\n"


def _emit_json_report(report: list[dict[str, Any]]) -> str:
    return json.dumps({"changes": report}, indent=2, sort_keys=True)


def _emit_validation_errors(errors: list[dict[str, Any]], fmt: str) -> str:
    if fmt == "json":
        return json.dumps(
            {"exit_code": EXIT_VALIDATION_FAIL, "errors": errors},
            indent=2,
            sort_keys=True,
        )
    lines = []
    for err in errors:
        code = err.get("code", "MIGRATION-PRODUCED-INVALID-V2")
        field = err.get("field", "<root>")
        detail = err.get("detail", "")
        lines.append(f"[{code}] field={field}\n  detail: {detail}")
    return "\n".join(lines)


# cycle-103 sprint-3 T3.4: provider-by-provider legacy walls (KF-002 layer 3
# observed pre-streaming thresholds). Operators should hand-tune for their
# fleet — these are conservative defaults.
_CYCLE103_LEGACY_DEFAULTS_BY_PROVIDER: dict[str, int] = {
    "openai": 24000,
    "anthropic": 36000,
    "google": 24000,
}


def _apply_cycle103_split(v2_dict: Any, report: list) -> None:
    """Walk every model entry that carries `max_input_tokens` and inject the
    `streaming_max_input_tokens` + `legacy_max_input_tokens` split fields
    when they're absent. Idempotent: re-running is a no-op for entries that
    already have the split.
    """
    providers = v2_dict.get("providers")
    if not isinstance(providers, dict):
        return
    for provider_name, prov in providers.items():
        if not isinstance(prov, dict):
            continue
        models = prov.get("models")
        if not isinstance(models, dict):
            continue
        legacy_default = _CYCLE103_LEGACY_DEFAULTS_BY_PROVIDER.get(
            provider_name, 0
        )
        for model_id, m in models.items():
            if not isinstance(m, dict):
                continue
            mi = m.get("max_input_tokens")
            if not isinstance(mi, int) or mi <= 0:
                continue
            changed = False
            if "streaming_max_input_tokens" not in m:
                m["streaming_max_input_tokens"] = mi
                changed = True
            if "legacy_max_input_tokens" not in m:
                # Prefer provider default; if unknown, use the existing
                # max_input_tokens (conservative: no behavior change vs
                # backward-compat path).
                m["legacy_max_input_tokens"] = (
                    legacy_default if legacy_default > 0 else mi
                )
                changed = True
            if changed:
                report.append(
                    {
                        "kind": "cycle103_split_injected",
                        "path": (
                            f"providers.{provider_name}."
                            f"models.{model_id}"
                        ),
                        "streaming_max_input_tokens": (
                            m["streaming_max_input_tokens"]
                        ),
                        "legacy_max_input_tokens": (
                            m["legacy_max_input_tokens"]
                        ),
                    }
                )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="loa migrate-model-config",
        description="Migrate model-config.yaml from v1 (cycle-095 vintage) to v2 (cycle-099).",
    )
    parser.add_argument("input", help="Path to v1 model-config.yaml")
    parser.add_argument(
        "-o", "--output", required=True, help="Path to write v2 model-config.yaml"
    )
    parser.add_argument(
        "--model-permissions",
        help=(
            "Optional path to cycle-026 standalone model-permissions.yaml; "
            "entries merged into per-model `permissions` block per DD-1 Option B."
        ),
    )
    parser.add_argument(
        "--schema",
        help=(
            "Optional v2 JSON Schema path (default: "
            ".claude/data/schemas/model-config-v2.schema.json relative to repo root)."
        ),
    )
    parser.add_argument(
        "--report-format",
        choices=("text", "json"),
        default="text",
        help="Format for change report (default: text).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run migration + validation but do not write the output file.",
    )
    parser.add_argument(
        "--no-validate",
        action="store_true",
        help=(
            "Skip post-migration v2 schema validation. Escape hatch — operator "
            "assumes responsibility for v2 conformance. Default is to validate."
        ),
    )
    parser.add_argument(
        "--cycle103-split",
        action="store_true",
        help=(
            "cycle-103 sprint-3 T3.4: post-migration, walk every model entry "
            "with `max_input_tokens` and inject `streaming_max_input_tokens` "
            "+ `legacy_max_input_tokens` if absent. `streaming_*` defaults to "
            "the existing `max_input_tokens` value; `legacy_*` defaults to "
            "the documented pre-streaming wall (openai=24000, anthropic=36000, "
            "google=24000, other=existing). Operator should hand-tune the "
            "values before merging if they have field-observed thresholds. "
            "Idempotent: re-running on a config that already has the split "
            "fields is a no-op for those entries."
        ),
    )
    parser.add_argument(
        "--to-v3",
        action="store_true",
        help=(
            "cycle-109 Sprint 1 T1.2: chain v1→v2→v3 (or v2→v3 directly) and "
            "validate against the v3 schema. Adds the capability-aware fields "
            "per SDD §3.1.1 with conservative defaults per SDD §3.1.2: "
            "effective_input_ceiling = min(50% × api_context_window, 30000); "
            "reasoning_class opt-in for claude-opus-4-*, gpt-5.5-pro, "
            "gemini-3.1-pro; recommended_for = allow-all 5-role list; "
            "failure_modes_observed = []; ceiling_calibration "
            "{source: conservative_default, stale_after_days: 30}; "
            "streaming_recovery with 60s (reasoning) or 30s (non-reasoning) "
            "first-token deadline. Idempotent on v3 input. When --to-v3 is "
            "set, the validation schema defaults to model-config-v3.schema.json."
        ),
    )
    parser.add_argument(
        "--calibrated-at",
        default="2026-05-13T00:00:00Z",
        help=(
            "ISO 8601 timestamp stamped on every ceiling_calibration block "
            "populated by --to-v3. Defaults to the cycle-109 Sprint 1 land "
            "date; CI/test fixtures pin this for determinism."
        ),
    )
    parser.add_argument(
        "--preserve-thresholds",
        action="store_true",
        help=(
            "cycle-109 followup B (#888): when --to-v3 populates "
            "effective_input_ceiling, source the value from the existing "
            "v2 threshold field (streaming_max_input_tokens, then "
            "legacy_max_input_tokens, then max_input_tokens) instead of "
            "the SDD §3.1.2 conservative formula. No-behavior-change "
            "migration semantics: pre-flight gate fires at the same "
            "threshold the substrate already operates at. Falls back to "
            "the formula when no v2 threshold field is present."
        ),
    )

    args = parser.parse_args(argv)

    input_path = Path(args.input)
    if not input_path.is_file():
        print(f"[INPUT-NOT-FOUND] {input_path}", file=sys.stderr)
        return EXIT_USAGE

    output_path = Path(args.output)

    # Resolve the schema path (CLI override or repo default).
    # --to-v3 routes to v3 schema by default; otherwise v2 schema.
    if args.schema:
        schema_path = Path(args.schema)
    else:
        repo_root = Path(__file__).resolve().parents[2]
        schema_filename = (
            "model-config-v3.schema.json" if args.to_v3
            else "model-config-v2.schema.json"
        )
        schema_path = (
            repo_root / ".claude" / "data" / "schemas" / schema_filename
        )
    if not args.no_validate and not schema_path.is_file():
        print(f"[SCHEMA-NOT-FOUND] {schema_path}", file=sys.stderr)
        return EXIT_USAGE

    # Load input (and optional cycle-026 model-permissions doc).
    try:
        v1 = _load_yaml(input_path)
    except Exception as exc:
        print(f"[INPUT-PARSE-ERROR] {input_path}: {exc}", file=sys.stderr)
        return EXIT_USAGE
    if v1 is None:
        print(f"[INPUT-EMPTY] {input_path}", file=sys.stderr)
        return EXIT_USAGE
    if not isinstance(v1, dict):
        print(
            f"[INPUT-NOT-MAPPING] {input_path}: top-level must be a mapping",
            file=sys.stderr,
        )
        return EXIT_USAGE

    permissions_doc: dict[str, Any] | None = None
    if args.model_permissions:
        perm_path = Path(args.model_permissions)
        if not perm_path.is_file():
            print(f"[PERMISSIONS-NOT-FOUND] {perm_path}", file=sys.stderr)
            return EXIT_USAGE
        try:
            permissions_doc = _load_yaml(perm_path)
        except Exception as exc:
            print(f"[PERMISSIONS-PARSE-ERROR] {perm_path}: {exc}", file=sys.stderr)
            return EXIT_USAGE

    v1_plain = _to_plain_dict(v1)
    permissions_plain = (
        _to_plain_dict(permissions_doc) if permissions_doc is not None else None
    )

    # Run migration. --to-v3 routes through migrate_to_latest (chains v1→v2→v3
    # or v2→v3 directly per cycle-109 Sprint 1 T1.2); otherwise legacy v1→v2.
    migrate_mod = _load_migrate_module()
    try:
        if args.to_v3:
            out_dict, report = migrate_mod.migrate_to_latest(
                v1_plain,
                target_version=3,
                model_permissions=permissions_plain,
                calibrated_at=args.calibrated_at,
                preserve_thresholds=args.preserve_thresholds,
            )
        else:
            out_dict, report = migrate_mod.migrate_v1_to_v2(
                v1_plain, permissions_plain
            )
    except migrate_mod.MigrationError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_VALIDATION_FAIL

    # cycle-103 sprint-3 T3.4: optional max_input_tokens streaming/legacy split.
    # Compatible with --to-v3 (operates on the v3 dict's provider/model tree).
    if args.cycle103_split:
        _apply_cycle103_split(out_dict, report)

    # Distinguish "operator-supplied invalid input" from "migrator-produced invalid output"
    # so the operator can route the fix correctly (review remediation G-M4).
    input_was_target_version = any(
        entry.get("kind") == "idempotent_noop" for entry in report
    )
    if args.to_v3:
        error_code = (
            "CONFIG-V3-INVALID" if input_was_target_version
            else "MIGRATION-PRODUCED-INVALID-V3"
        )
    else:
        error_code = (
            "CONFIG-V2-INVALID" if input_was_target_version
            else "MIGRATION-PRODUCED-INVALID-V2"
        )

    # Post-migration validation (default on).
    if not args.no_validate:
        errors = _validate_v2(out_dict, schema_path, error_code=error_code)
        if errors:
            sys.stderr.write(_emit_validation_errors(errors, args.report_format))
            sys.stderr.write("\n")
            return EXIT_VALIDATION_FAIL

    # Emit report (stdout — operator-readable summary of what changed).
    if args.report_format == "json":
        sys.stdout.write(_emit_json_report(report))
    else:
        sys.stdout.write(_emit_text_report(report))

    # Write output unless --dry-run.
    if not args.dry_run:
        try:
            _dump_yaml(out_dict, output_path)
        except SymlinkRefusedError as exc:
            print(f"[OUTPUT-IS-SYMLINK] {exc}", file=sys.stderr)
            return EXIT_USAGE
        except Exception as exc:
            print(f"[OUTPUT-WRITE-ERROR] {output_path}: {exc}", file=sys.stderr)
            return EXIT_USAGE

    return EXIT_SUCCESS


if __name__ == "__main__":
    raise SystemExit(main())
