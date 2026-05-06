#!/usr/bin/env python3
"""golden_resolution.py — cycle-099 Sprint 2D Python golden test runner.

Reads each .yaml fixture under tests/fixtures/model-resolution/ (sorted by
filename) and runs the canonical Python resolver
(`.claude/scripts/lib/model-resolver.py`) against `input.{framework_defaults,
operator_config, runtime_state}` for each (skill, role) tuple declared in
`expected.resolutions[]`. Emits one canonical JSON line per resolution to
stdout.

Output schema MUST match the bash runner (`tests/bash/golden_resolution.sh`)
byte-for-byte. The cross-runtime-diff CI gate
(`.github/workflows/cross-runtime-diff.yml`) byte-compares Python vs bash
output; mismatch fails the build per SDD §7.6.2.

Sprint 2D scope (T2.6): the full FR-3.9 6-stage resolver. Stages 1-6 emit
detailed `resolution_path` arrays; pre-resolution validation (stage 0)
covers IMP-004 conflicts. Compare to Sprint 1D's alias-lookup-only subset.

Output shape (per `model-resolver-output.schema.json` with optional `fixture`
context tag):

    Success: {fixture, skill, role, resolved_provider, resolved_model_id,
              resolution_path}
    Error:   {fixture, skill, role, error: {code, stage_failed, detail}}

Sort order: by (fixture-filename ascending, skill ascending, role ascending).

Usage:
    python3 tests/python/golden_resolution.py > python-resolution-output.jsonl

Env-var test escapes (each REQUIRES `LOA_GOLDEN_TEST_MODE=1` OR running under
bats — mirror cycle-099 sprint-1B `LOA_MODEL_RESOLVER_TEST_MODE` pattern):

    LOA_GOLDEN_PROJECT_ROOT  — override project root (default: derived from __file__)
    LOA_GOLDEN_FIXTURES_DIR  — override fixtures directory
    LOA_GOLDEN_RESOLVER_PY   — override path to model-resolver.py module

Without TEST_MODE, the override is ignored and a warning is emitted to stderr.
This prevents an attacker who controls env vars from redirecting resolution
to attacker-controlled Python code.
"""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path

import yaml


# ----------------------------------------------------------------------------
# Test-mode override gating (cycle-099 LOA_*_TEST_MODE pattern)
# ----------------------------------------------------------------------------

def _golden_test_mode_active() -> bool:
    """env-override gate parity with cypherpunk CRIT-3 from PR #735.

    Each LOA_GOLDEN_* override REQUIRES `LOA_GOLDEN_TEST_MODE=1` OR
    `BATS_TEST_DIRNAME` (set by bats), else override is IGNORED.
    """
    return (
        os.environ.get("LOA_GOLDEN_TEST_MODE") == "1"
        or bool(os.environ.get("BATS_TEST_DIRNAME"))
    )


def _golden_resolve_path(env_var: str, default: Path) -> Path:
    val = os.environ.get(env_var)
    if val:
        if _golden_test_mode_active():
            print(f"[GOLDEN] override active: {env_var}={val}", file=sys.stderr)
            return Path(val)
        else:
            print(
                f"[GOLDEN] WARNING: {env_var} set but LOA_GOLDEN_TEST_MODE!=1 "
                "and not running under bats — IGNORED",
                file=sys.stderr,
            )
    return default


# ----------------------------------------------------------------------------
# Path resolution
# ----------------------------------------------------------------------------

_PROJECT_ROOT_DEFAULT = Path(__file__).resolve().parent.parent.parent
PROJECT_ROOT = _golden_resolve_path("LOA_GOLDEN_PROJECT_ROOT", _PROJECT_ROOT_DEFAULT)
FIXTURES_DIR = _golden_resolve_path(
    "LOA_GOLDEN_FIXTURES_DIR",
    PROJECT_ROOT / "tests" / "fixtures" / "model-resolution",
)
RESOLVER_PATH = _golden_resolve_path(
    "LOA_GOLDEN_RESOLVER_PY",
    PROJECT_ROOT / ".claude" / "scripts" / "lib" / "model-resolver.py",
)


# ----------------------------------------------------------------------------
# Resolver module loading
# ----------------------------------------------------------------------------

def _load_resolver_module() -> object:
    """Load the canonical Python resolver via importlib (file path → module).

    Per cycle-099 sprint-2B model-overlay-hook.py CYP-F8 lesson, we do NOT use
    sys.path.insert — that pollutes downstream import resolution. importlib's
    spec_from_file_location is the cleaner pattern.
    """
    if not RESOLVER_PATH.is_file():
        raise FileNotFoundError(
            f"golden_resolution.py: model-resolver.py not found at {RESOLVER_PATH}"
        )
    spec = importlib.util.spec_from_file_location(
        "_loa_model_resolver_for_golden", RESOLVER_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not build module spec for {RESOLVER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ----------------------------------------------------------------------------
# Main runner
# ----------------------------------------------------------------------------

def _emit_result(fixture: str, result: dict, dump_canonical_json) -> None:
    """Emit one canonical JSON line per resolution result, with `fixture` tag."""
    decorated = dict(result)  # shallow copy — don't mutate caller
    decorated["fixture"] = fixture
    sys.stdout.write(dump_canonical_json(decorated))
    sys.stdout.write("\n")


def main() -> int:
    if not FIXTURES_DIR.is_dir():
        print(
            f"golden_resolution.py: fixtures dir {FIXTURES_DIR} not present",
            file=sys.stderr,
        )
        return 2

    try:
        resolver = _load_resolver_module()
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"golden_resolution.py: {exc}", file=sys.stderr)
        return 2

    resolve = resolver.resolve  # type: ignore[attr-defined]
    dump_canonical_json = resolver.dump_canonical_json  # type: ignore[attr-defined]

    # Sort by filename for deterministic output ordering across runtimes.
    fixtures = sorted(FIXTURES_DIR.glob("*.yaml"))

    for fixture_path in fixtures:
        fixture_name = fixture_path.stem
        try:
            with fixture_path.open("r", encoding="utf-8") as fh:
                doc = yaml.safe_load(fh) or {}
        except yaml.YAMLError:
            # Uniform error marker (matches bash runner's malformed-YAML path)
            sys.stdout.write(
                dump_canonical_json({
                    "fixture": fixture_name,
                    "error": {
                        "code": "[YAML-PARSE-FAILED]",
                        "stage_failed": 0,
                        "detail": "fixture YAML failed to parse",
                    },
                })
            )
            sys.stdout.write("\n")
            continue

        merged_config = doc.get("input") or {}
        expected = doc.get("expected") or {}
        resolutions = expected.get("resolutions") or []

        if not isinstance(resolutions, list) or len(resolutions) == 0:
            # Fixture has no `expected.resolutions[]` — emit a uniform marker
            # so cross-runtime parity holds for malformed/incomplete fixtures.
            sys.stdout.write(
                dump_canonical_json({
                    "fixture": fixture_name,
                    "error": {
                        "code": "[NO-EXPECTED-RESOLUTIONS]",
                        "stage_failed": 0,
                        "detail": "fixture lacks expected.resolutions[] block",
                    },
                })
            )
            sys.stdout.write("\n")
            continue

        # Sort declared resolutions by (skill, role) for deterministic ordering.
        # Per parity bats P6, output sort order is (fixture, skill, role).
        resolutions_sorted = sorted(
            (
                r for r in resolutions
                if isinstance(r, dict)
                and isinstance(r.get("skill"), str)
                and isinstance(r.get("role"), str)
            ),
            key=lambda r: (r["skill"], r["role"]),
        )

        for entry in resolutions_sorted:
            result = resolve(merged_config, entry["skill"], entry["role"])
            _emit_result(fixture_name, result, dump_canonical_json)

    return 0


if __name__ == "__main__":
    sys.exit(main())
