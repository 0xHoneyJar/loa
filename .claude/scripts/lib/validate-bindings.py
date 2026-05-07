#!/usr/bin/env python3
"""validate-bindings.py — cycle-099 Sprint 2F (T2.12).

`model-invoke --validate-bindings` implementation per SDD §5.2 + FR-5.6.

CONTRACT
========

Reads the effective merged config (framework_defaults + operator_config +
runtime_state), enumerates all `(skill, role)` pairs, and resolves each via
the canonical `model-resolver.resolve()` 6-stage algorithm. Emits a JSON
report per SDD §5.2 to stdout. Makes ZERO API calls (dry-run).

Inputs
------
* `--merged-config <path>` (required) — path to the merged config YAML.
  Shape: `{framework_defaults: {...}, operator_config: {...}, runtime_state: {...}}`.
  In production this is produced by `model-overlay-hook.py`; for unit
  testing, callers can hand-author the merged shape directly.
* `--format json|text` (default: `json`) — output formatting.
* `--diff-bindings` — compare effective resolution against framework-only
  resolution; emit `[BINDING-OVERRIDDEN]` to stderr per SDD §1.5.2 for each
  divergent binding.
* `--config <path>` — alias for `--merged-config` to match SDD §5.2 surface.

Enumeration
-----------
For each `(skill, role)` pair from:
* `framework_defaults.agents.<skill>` where `model:` is set AND not `native`
  → emit `(skill, "primary")` (single-role implicit per cycle-095 schema).
* `operator_config.skill_models.<skill>.<role>` → emit each `(skill, role)`.

Pairs are deduplicated on `(skill, role)`; on collision, the resolver's S2
takes precedence over S5 by FR-3.9, so the output is identical regardless of
which "side" we counted from.

Outputs
-------
* stdout: JSON or pretty-text per `--format`.
* stderr: `[BINDING-OVERRIDDEN]` lines under `--diff-bindings`.
* Exit 0: all bindings resolve cleanly.
* Exit 1: ≥1 unresolved binding (FR-3.8 violation).
* Exit 78: config error — file missing, malformed YAML, schema violation.
* Exit 2: usage error — unknown `--format` value, etc.

Security
--------
JSON output is passed through `log-redactor.redact` before emission per
SDD §5.6 (IMP-002 HIGH_CONSENSUS 860). URL `userinfo` and 6 query-string
secret patterns are masked. The redactor uses `spec_from_file_location`
(NOT sys.path manipulation) per the cycle-099 CYP-F8 convention.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

# Exit codes per SDD §5.2.
EXIT_OK = 0
EXIT_UNRESOLVED = 1
EXIT_USAGE = 2
EXIT_CONFIG = 78

SCHEMA_VERSION = "1.0.0"
COMMAND = "validate-bindings"

_LIB_DIR = Path(__file__).resolve().parent


def _load_module(module_name: str, file_name: str) -> Any:
    """spec_from_file_location import (CYP-F8: no sys.path mutation)."""
    spec = importlib.util.spec_from_file_location(module_name, _LIB_DIR / file_name)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not locate {file_name} at {_LIB_DIR}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_resolver_module = _load_module("_loa_model_resolver", "model-resolver.py")
_redactor_module = _load_module("_loa_log_redactor", "log-redactor.py")
resolve = _resolver_module.resolve
dump_canonical_json = _resolver_module.dump_canonical_json
redact = _redactor_module.redact


def _enumerate_bindings(merged_config: dict) -> list[tuple[str, str]]:
    """Enumerate all (skill, role) pairs to resolve.

    Source 1: `framework_defaults.agents.<skill>.model` (NOT 'native') →
        emit (skill, 'primary'). Per cycle-095 schema, framework agents are
        single-model; the implicit role is 'primary'.

    Source 2: `operator_config.skill_models.<skill>.<role>` → emit each.

    Output is sorted by (skill, role) for deterministic ordering.
    Deduped — on collision, the (skill, role) appears once.
    """
    pairs: set[tuple[str, str]] = set()

    framework = merged_config.get("framework_defaults") or {}
    if not isinstance(framework, dict):
        framework = {}
    agents = framework.get("agents") or {}
    if isinstance(agents, dict):
        for skill, block in agents.items():
            if not isinstance(skill, str) or not isinstance(block, dict):
                continue
            model = block.get("model")
            if isinstance(model, str) and model and model != "native":
                pairs.add((skill, "primary"))
            elif "default_tier" in block:
                # `agents.<skill>` MAY use `default_tier` instead of `model:`
                # per FR-3.9 stage 5b. Still resolves to a (skill, 'primary')
                # binding through the resolver.
                pairs.add((skill, "primary"))

    operator = merged_config.get("operator_config") or {}
    if not isinstance(operator, dict):
        operator = {}
    skill_models = operator.get("skill_models") or {}
    if isinstance(skill_models, dict):
        for skill, role_block in skill_models.items():
            if not isinstance(skill, str) or not isinstance(role_block, dict):
                continue
            for role in role_block.keys():
                if isinstance(role, str):
                    pairs.add((skill, role))

    return sorted(pairs)


def _compute_tracing_fingerprint(resolution_path: list) -> str:
    """12-char SHA256 prefix per SDD §6.4 correlation contract."""
    canonical = json.dumps(resolution_path, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:12]


def _build_binding_record(skill: str, role: str, result: dict) -> dict:
    """Convert resolver output into the SDD §5.2 binding-record shape."""
    record: dict = {"skill": skill, "role": role}
    if "error" in result:
        # Unresolved — surface the error structure for operator triage.
        record["error"] = result["error"]
        record["resolution_path"] = result.get("resolution_path", [])
    else:
        record["resolved_provider"] = result.get("resolved_provider")
        record["resolved_model_id"] = result.get("resolved_model_id")
        record["resolution_path"] = result.get("resolution_path", [])
        record["tracing_fingerprint"] = _compute_tracing_fingerprint(
            record["resolution_path"]
        )
    return record


def _is_legacy_path(resolution_path: list) -> bool:
    """Check if resolution went through stage 4 (legacy shape)."""
    if not isinstance(resolution_path, list):
        return False
    for entry in resolution_path:
        if isinstance(entry, dict) and entry.get("stage") == 4 and entry.get("outcome") == "hit":
            return True
    return False


def _build_summary(bindings: list[dict]) -> dict:
    """Aggregate counts per SDD §5.2 summary block."""
    total = len(bindings)
    unresolved = sum(1 for b in bindings if "error" in b)
    resolved = total - unresolved
    legacy_warnings = sum(
        1 for b in bindings if _is_legacy_path(b.get("resolution_path", []))
    )
    return {
        "total_bindings": total,
        "resolved": resolved,
        "unresolved": unresolved,
        "legacy_shape_warnings": legacy_warnings,
    }


def _diff_bindings(merged_config: dict, bindings: list[dict]) -> list[dict]:
    """Per SDD §1.5.2: re-resolve each binding against framework_defaults
    ONLY (no operator overlay) and emit `[BINDING-OVERRIDDEN]` to stderr for
    each divergent pair.

    Returns a list of overridden-binding records for embedding in the JSON
    output (`overridden` key) so machine consumers can correlate.
    """
    framework_only: dict = {
        "framework_defaults": merged_config.get("framework_defaults") or {},
        "operator_config": {},
        "runtime_state": merged_config.get("runtime_state") or {},
    }
    overridden: list[dict] = []
    for binding in bindings:
        skill = binding["skill"]
        role = binding["role"]
        compiled = resolve(framework_only, skill, role)
        if "error" in compiled:
            compiled_id = "ERROR:" + (compiled.get("error", {}).get("code", "?"))
        else:
            compiled_id = (
                f"{compiled.get('resolved_provider', '?')}:"
                f"{compiled.get('resolved_model_id', '?')}"
            )
        if "error" in binding:
            effective_id = "ERROR:" + (binding.get("error", {}).get("code", "?"))
        else:
            effective_id = (
                f"{binding.get('resolved_provider', '?')}:"
                f"{binding.get('resolved_model_id', '?')}"
            )
        if compiled_id != effective_id:
            line = (
                f"[BINDING-OVERRIDDEN] skill={skill} role={role} "
                f"compiled={compiled_id} effective={effective_id} source=runtime_overlay"
            )
            sys.stderr.write(redact(line) + "\n")
            overridden.append(
                {
                    "skill": skill,
                    "role": role,
                    "compiled": compiled_id,
                    "effective": effective_id,
                    "source": "runtime_overlay",
                }
            )
    return overridden


def _format_text(report: dict) -> str:
    """Pretty-print the JSON report as a human-readable text block.

    NOT machine-parseable (per SDD §5.2 — text format is operator-friendly).
    Intentionally NOT just "pretty JSON" so the test framework can confirm
    `--format text` produces structurally distinct output.
    """
    lines: list[str] = []
    summary = report.get("summary", {})
    lines.append(f"Validate-Bindings Report (schema v{report.get('schema_version', '?')})")
    lines.append("=" * 60)
    lines.append(
        f"Total bindings: {summary.get('total_bindings', 0)}    "
        f"Resolved: {summary.get('resolved', 0)}    "
        f"Unresolved: {summary.get('unresolved', 0)}    "
        f"Legacy warnings: {summary.get('legacy_shape_warnings', 0)}"
    )
    lines.append("-" * 60)
    for binding in report.get("bindings", []):
        skill = binding.get("skill", "?")
        role = binding.get("role", "?")
        if "error" in binding:
            err = binding["error"]
            err_code = err.get("code", "?") if isinstance(err, dict) else "?"
            lines.append(f"  [UNRESOLVED] {skill}.{role}  error={err_code}")
        else:
            provider = binding.get("resolved_provider", "?")
            model_id = binding.get("resolved_model_id", "?")
            fp = binding.get("tracing_fingerprint", "?")
            lines.append(f"  [OK] {skill}.{role}  ->  {provider}:{model_id}  ({fp})")
    if report.get("overridden"):
        lines.append("-" * 60)
        lines.append("Runtime-overlay overrides:")
        for ov in report["overridden"]:
            lines.append(
                f"  {ov['skill']}.{ov['role']}: compiled={ov['compiled']} "
                f"effective={ov['effective']}"
            )
    return "\n".join(lines) + "\n"


def _load_yaml(path: Path) -> dict:
    """Load YAML or raise. Caller maps exception to EXIT_CONFIG."""
    import yaml  # function-scoped (resolver-style)

    with open(path, "r", encoding="utf-8") as fh:
        loaded = yaml.safe_load(fh)
    if not isinstance(loaded, dict):
        raise ValueError(f"top-level YAML at {path} is not a mapping")
    return loaded


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="validate-bindings",
        description="cycle-099 FR-5.6 model-invoke --validate-bindings (Sprint 2F T2.12)",
        # SDD §5.2 says exit 2 on usage error. argparse defaults to 2 for
        # ArgumentError, which matches.
    )
    # Both --merged-config and --config accepted (SDD §5.2 says --config; the
    # test surface uses --merged-config to disambiguate from operator-side
    # `.loa.config.yaml`).
    parser.add_argument("--merged-config", dest="config_path")
    parser.add_argument("--config", dest="config_path_alt")
    parser.add_argument("--format", choices=["json", "text"], default="json")
    parser.add_argument("--diff-bindings", action="store_true")
    parser.add_argument("--verbose", action="store_true")

    try:
        args = parser.parse_args(argv)
    except SystemExit as e:
        # argparse exits 2 on usage error — propagate per SDD §5.2.
        return e.code if isinstance(e.code, int) else EXIT_USAGE

    config_path = args.config_path or args.config_path_alt
    if not config_path:
        sys.stderr.write(
            "[VALIDATE-BINDINGS] ERROR: --merged-config or --config required\n"
        )
        return EXIT_USAGE

    cfg_path = Path(config_path)
    if not cfg_path.is_file():
        sys.stderr.write(
            f"[VALIDATE-BINDINGS] ERROR: config file not found: {cfg_path}\n"
        )
        return EXIT_CONFIG

    try:
        merged = _load_yaml(cfg_path)
    except Exception as e:
        sys.stderr.write(
            f"[VALIDATE-BINDINGS] ERROR: failed to load config: "
            f"{type(e).__name__}: {e}\n"
        )
        return EXIT_CONFIG

    pairs = _enumerate_bindings(merged)
    bindings: list[dict] = []
    for skill, role in pairs:
        result = resolve(merged, skill, role)
        bindings.append(_build_binding_record(skill, role, result))

    summary = _build_summary(bindings)
    overridden_records: list[dict] = []
    if args.diff_bindings:
        overridden_records = _diff_bindings(merged, bindings)

    exit_code = EXIT_OK if summary["unresolved"] == 0 else EXIT_UNRESOLVED

    report: dict = {
        "schema_version": SCHEMA_VERSION,
        "command": COMMAND,
        "exit_code": exit_code,
        "summary": summary,
        "bindings": bindings,
    }
    if overridden_records:
        report["overridden"] = overridden_records

    if args.format == "text":
        sys.stdout.write(redact(_format_text(report)))
    else:
        sys.stdout.write(redact(dump_canonical_json(report)))
        sys.stdout.write("\n")

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
