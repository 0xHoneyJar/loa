#!/usr/bin/env python3
"""golden_resolution.py — cycle-099 Sprint 1D Python runner.

Reads each .yaml fixture under tests/fixtures/model-resolution/ (sorted by
filename), extracts `sprint_1d_query.alias`, performs alias resolution
against the SAME registry the bash runner uses (parsed directly from
.claude/scripts/generated-model-maps.sh), and emits one canonical JSON line
per fixture to stdout.

Output schema MUST be byte-identical to tests/bash/golden_resolution.sh
(cross-runtime parity per SDD §7.6.2). The cross-runtime-diff CI gate
(.github/workflows/cross-runtime-diff.yml) byte-compares all three runtimes'
emitted output; mismatch fails the build.

Sprint 1D scope: alias-lookup subset of FR-3.9. Stages 3-6 deferred to
Sprint 2 T2.6; runners emit a uniform `deferred_to: "sprint-2-T2.6"` marker.

Usage:
    python3 tests/python/golden_resolution.py > python-resolution-output.jsonl
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

import yaml

def _golden_test_mode_active() -> bool:
    """cypherpunk CRIT-3 (PR #735 review): env-override gate parity. Mirror
    the model-resolver.sh::LOA_MODEL_RESOLVER_TEST_MODE pattern. Each
    LOA_GOLDEN_* override REQUIRES `LOA_GOLDEN_TEST_MODE=1` OR
    `BATS_TEST_DIRNAME` (set by bats), else the override is IGNORED.
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


_PROJECT_ROOT_DEFAULT = Path(__file__).resolve().parent.parent.parent
PROJECT_ROOT = _golden_resolve_path("LOA_GOLDEN_PROJECT_ROOT", _PROJECT_ROOT_DEFAULT)
FIXTURES_DIR = _golden_resolve_path(
    "LOA_GOLDEN_FIXTURES_DIR",
    PROJECT_ROOT / "tests" / "fixtures" / "model-resolution",
)
GENERATED_MAPS = _golden_resolve_path(
    "LOA_GOLDEN_GENERATED_MAPS",
    PROJECT_ROOT / ".claude" / "scripts" / "generated-model-maps.sh",
)


def _parse_generated_maps(path: Path) -> tuple[dict[str, str], dict[str, str]]:
    """Parse the bash associative-array form from generated-model-maps.sh.

    Returns (model_providers, model_ids) — same shape as the bash MODEL_PROVIDERS
    and MODEL_IDS arrays. Idempotent: every model_id is also a key resolving
    to itself in MODEL_IDS.

    The parser is line-oriented and tolerant of:
      - leading whitespace
      - trailing comments (after the value's closing quote)
      - inline comment lines starting with #

    It is NOT a full bash parser; it relies on the codegen output's strict
    `["key"]="value"` format. Drift in that format breaks the parser; the
    drift gate catches it because cross-runtime parity also breaks.
    """
    text = path.read_text(encoding="utf-8")

    def _extract_array(name: str) -> dict[str, str]:
        # Match `declare -A NAME=(\n ...entries... \n)`. Capture entries block.
        # Use re.DOTALL so . matches newlines inside the body.
        pattern = rf"declare\s+-A\s+{re.escape(name)}=\s*\(\s*(.*?)\s*\)"
        m = re.search(pattern, text, re.DOTALL)
        if not m:
            raise ValueError(f"declare -A {name} not found in {path}")
        body = m.group(1)
        result: dict[str, str] = {}
        # Each entry is `["key"]="value"` with optional surrounding whitespace.
        # The codegen emits double-quoted keys + values; tolerate single-quoted too.
        entry_re = re.compile(r"""\[\s*"([^"]*)"\s*\]\s*=\s*"([^"]*)"\s*""")
        for entry_m in entry_re.finditer(body):
            key, val = entry_m.group(1), entry_m.group(2)
            # In bash associative arrays a duplicate key silently overwrites
            # earlier occurrences; mirror that behavior.
            result[key] = val
        return result

    return _extract_array("MODEL_PROVIDERS"), _extract_array("MODEL_IDS")


def _emit(record: dict) -> None:
    """Emit one canonical JSON line (sorted keys, no whitespace) to stdout.

    gp CRITICAL-2 (PR #735 review): `ensure_ascii=False` is REQUIRED so that
    non-ASCII Unicode in values is emitted as literal UTF-8 bytes, matching
    bash `jq -c` and TS `JSON.stringify` (both of which emit literal UTF-8).
    Without this flag, Python emits `\\uXXXX` escapes that diverge from
    bash/TS — invisible today (all values are ASCII) but a latent
    cross-runtime parity bug for Sprint 2 when operator-supplied IDs may
    include non-ASCII chars.
    """
    print(json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False))


def main() -> int:
    if not FIXTURES_DIR.is_dir():
        print(f"golden_resolution.py: fixtures dir {FIXTURES_DIR} not present", file=sys.stderr)
        return 2
    if not GENERATED_MAPS.is_file():
        print(f"golden_resolution.py: generated-maps {GENERATED_MAPS} not present", file=sys.stderr)
        return 2

    model_providers, model_ids = _parse_generated_maps(GENERATED_MAPS)

    # Sort by filename for deterministic output ordering across runtimes.
    fixtures = sorted(FIXTURES_DIR.glob("*.yaml"))

    for fixture_path in fixtures:
        fixture_name = fixture_path.stem
        try:
            with fixture_path.open("r", encoding="utf-8") as f:
                doc = yaml.safe_load(f) or {}
        except yaml.YAMLError as exc:
            _emit({
                "error": f"yaml-parse-failed: {exc}",
                "fixture": fixture_name,
                "subset_supported": False,
            })
            continue

        query = doc.get("sprint_1d_query") or {}
        alias_input = query.get("alias")
        # gp HIGH-2 + cypherpunk CRIT-2 (PR #735 review): type-discrimination
        # matches bash's `yq | tag` check. Distinct error markers for missing
        # field vs invalid type vs empty string so debugging is unambiguous.
        if alias_input is None:
            _emit({
                "error": "missing-sprint_1d_query-alias",
                "fixture": fixture_name,
                "subset_supported": False,
            })
            continue
        if not isinstance(alias_input, str):
            # Map Python types to YAML tags so bash + python emit identical error markers.
            type_to_tag = {bool: "!!bool", int: "!!int", float: "!!float", list: "!!seq", dict: "!!map"}
            tag = type_to_tag.get(type(alias_input), f"!!{type(alias_input).__name__}")
            _emit({
                "error": f"invalid-alias-type:{tag}",
                "fixture": fixture_name,
                "subset_supported": False,
            })
            continue
        if not alias_input:
            _emit({
                "error": "missing-sprint_1d_query-alias",
                "fixture": fixture_name,
                "subset_supported": False,
            })
            continue

        # Stage 1 explicit pin: provider:model_id
        if ":" in alias_input:
            provider_part, _, model_part = alias_input.partition(":")
            if model_part in model_providers:
                _emit({
                    "fixture": fixture_name,
                    "input_alias": alias_input,
                    "resolved_model_id": model_part,
                    "resolved_provider": provider_part,
                    "subset_supported": True,
                })
                continue
            _emit({
                "deferred_to": "sprint-2-T2.6",
                "fixture": fixture_name,
                "input_alias": alias_input,
                "subset_supported": False,
            })
            continue

        # Plain alias: resolve via MODEL_IDS / MODEL_PROVIDERS.
        # Python dicts have no prototype so `key in dict` is hasOwn-equivalent
        # (no equivalent of cypherpunk CRIT-1 needed here). bash assoc-arrays
        # use `${MAP[key]+_}` which is also hasOwn semantically. Only TS's
        # `in` operator walks prototypes — fixed via hasKey().
        if alias_input in model_ids:
            resolved_id = model_ids[alias_input]
            # MODEL_PROVIDERS may key on the canonical model_id OR the alias.
            # Match the bash fallback chain: provider[resolved_id] → provider[alias] → "unknown".
            resolved_provider = (
                model_providers.get(resolved_id)
                or model_providers.get(alias_input)
                or "unknown"
            )
            _emit({
                "fixture": fixture_name,
                "input_alias": alias_input,
                "resolved_model_id": resolved_id,
                "resolved_provider": resolved_provider,
                "subset_supported": True,
            })
        else:
            _emit({
                "deferred_to": "sprint-2-T2.6",
                "fixture": fixture_name,
                "input_alias": alias_input,
                "subset_supported": False,
            })

    return 0


if __name__ == "__main__":
    sys.exit(main())
