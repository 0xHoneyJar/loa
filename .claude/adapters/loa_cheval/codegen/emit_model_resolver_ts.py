"""emit_model_resolver_ts — render the TS port of the cycle-099 FR-3.9
6-stage model resolver from the canonical Python source via Jinja2.

Per cycle-099 SDD §1.5.1 IMP-001, the TS resolver in Bridgebuilder runtime
(latency-critical hot path) cannot fork Python per call. Instead, this codegen
extracts the canonical resolver's constants (stage labels, error codes, tier
names, control-byte regex pattern) and substitutes them into
.claude/scripts/lib/codegen/model-resolver.ts.j2 to produce
.claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts.

Determinism: source-content SHA-256 is recorded in the generated header. CI
runs this module + diffs the committed output → drift = PR fail. The drift
gate also cross-checks the embedded hash against a fresh hash of the canonical
source, catching tampered-canonical-with-matching-regen scenarios.

Usage:
    python3 -m loa_cheval.codegen.emit_model_resolver_ts > out.ts
    python3 -m loa_cheval.codegen.emit_model_resolver_ts --check  # exit 3 on drift

Mirrors `emit_endpoint_validator_ts` (sprint-1E.c.1) verbatim. Kept separate
so each generated artifact has its own canonical source / hash / drift gate.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import sys
from pathlib import Path
from typing import Any

GENERATOR_VERSION = "1.0"


def _project_root() -> Path:
    # this file path:
    #   <root>/.claude/adapters/loa_cheval/codegen/emit_model_resolver_ts.py
    # parents[4] = <root>
    return Path(__file__).resolve().parents[4]


def _load_canonical() -> tuple[Any, Path]:
    """Load .claude/scripts/lib/model-resolver.py via spec_loader.

    The file uses a dash in its name which Python can't import normally.
    Mirrors sprint-1E.c.1's CYP-F8 pattern: spec_from_file_location + register
    in sys.modules BEFORE exec_module.

    Cypherpunk MED-1 (sprint-2D.c review): canonical_path is realpath-resolved
    + verified as a regular file under the expected lib directory. A symlink
    target outside the canonical tree would be rejected. Mirrors the cycle-098
    L3 + cycle-099 sprint-2B CYP-F8 pattern (`grimoires/loa/runbooks/...` +
    "ALWAYS use realpath + project-root containment").
    """
    expected_dir = (_project_root() / ".claude" / "scripts" / "lib").resolve()
    canonical_path = expected_dir / "model-resolver.py"
    if canonical_path.is_symlink():
        raise RuntimeError(
            f"canonical at {canonical_path} is a symlink — refuse to load "
            f"(cypherpunk MED-1: tampered-canonical defense)"
        )
    if not canonical_path.is_file():
        raise FileNotFoundError(f"canonical not found: {canonical_path}")
    resolved = canonical_path.resolve()
    if not resolved.is_relative_to(expected_dir):
        raise RuntimeError(
            f"canonical resolves to {resolved} which is outside expected dir "
            f"{expected_dir}"
        )
    module_name = "model_resolver_canonical"
    spec = importlib.util.spec_from_file_location(module_name, canonical_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load spec for {canonical_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(module_name, None)
        raise
    return module, canonical_path


def _hash_source(canonical_path: Path) -> str:
    """Stable SHA-256 over the canonical Python source file. Emitted in the
    generated TS header so a manual edit to the canonical without regenerating
    the TS file produces a header mismatch the drift gate catches."""
    return hashlib.sha256(canonical_path.read_bytes()).hexdigest()


def _build_context(canonical: Any, source_hash: str) -> dict[str, Any]:
    """Extract constants from the canonical resolver and assemble Jinja2 context."""
    # Stage labels (pinned by schema)
    stage_labels = {
        "S1": canonical.STAGE1_LABEL,
        "S2": canonical.STAGE2_LABEL,
        "S3": canonical.STAGE3_LABEL,
        "S4": canonical.STAGE4_LABEL,
        "S5": canonical.STAGE5_LABEL,
        "S6": canonical.STAGE6_LABEL,
    }
    # Error codes (pinned by schema)
    error_codes = {
        "TIER_NO_MAPPING":          canonical.ERR_TIER_NO_MAPPING,
        "OVERRIDE_UNKNOWN":         canonical.ERR_OVERRIDE_UNKNOWN,
        "EXTRA_OVERRIDE_CONFLICT":  canonical.ERR_EXTRA_OVERRIDE_CONFLICT,
        "NO_RESOLUTION":            canonical.ERR_NO_RESOLUTION,
        "INPUT_CONTROL_BYTE":       canonical.ERR_INPUT_CONTROL_BYTE,
    }
    # Tier names — frozenset → sorted list for deterministic ordering
    tier_names = sorted(canonical.TIER_NAMES)
    # Control-byte regex pattern source — ensure JS-compatible
    # Python's `\x00-\x08\x0B-\x1F` translates to the same regex char class
    # in JS. The pattern is substituted RAW into a JS regex literal
    # `/{{ ctrl_byte_pattern }}/`, so any unescaped `/` would corrupt the
    # literal. gp MED-1 (sprint-2D.c review): assert no `/` to fail-fast at
    # build time rather than ship a broken regex.
    ctrl_byte_pattern = canonical._CTRL_BYTE_RE.pattern
    if "/" in ctrl_byte_pattern:
        raise RuntimeError(
            f"ctrl_byte_pattern contains `/` which would corrupt the JS "
            f"regex literal in the template: {ctrl_byte_pattern!r}"
        )
    return {
        "source_hash": source_hash,
        "generator_version": GENERATOR_VERSION,
        "stage_labels": stage_labels,
        "error_codes": error_codes,
        "tier_names": tier_names,
        "ctrl_byte_pattern": ctrl_byte_pattern,
    }


def _render(context: dict[str, Any]) -> str:
    """Render the Jinja2 template.

    The sprint-1E.c.1 emit module registers `ord` + `ts_escape_cp` filters
    for non-BMP codepoint escapes in control-byte arrays; this template
    doesn't substitute any character literals (only string constants via
    `tojson`), so those filters are not registered here. If a future
    template-edit needs them, restore from sprint-1E.c.1's emit module.
    """
    from jinja2 import Environment, FileSystemLoader, StrictUndefined

    template_dir = _project_root() / ".claude" / "scripts" / "lib" / "codegen"
    env = Environment(
        loader=FileSystemLoader(str(template_dir)),
        keep_trailing_newline=True,
        undefined=StrictUndefined,
        autoescape=False,
    )
    template = env.get_template("model-resolver.ts.j2")
    return template.render(**context)


def emit() -> str:
    """Run the full pipeline and return the rendered TS as a string."""
    canonical, canonical_path = _load_canonical()
    source_hash = _hash_source(canonical_path)
    context = _build_context(canonical, source_hash)
    return _render(context)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="emit_model_resolver_ts",
        description=(
            "Render model-resolver.generated.ts from the canonical Python "
            "source + Jinja2 template."
        ),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help=(
            "Compare a fresh codegen run against the committed file; exit 3 "
            "on drift, 0 on match. CI uses this for the drift gate."
        ),
    )
    parser.add_argument(
        "--out",
        help=(
            "Write to this path instead of stdout. Default: stdout."
        ),
    )
    args = parser.parse_args(argv)

    fresh = emit()

    if args.check:
        committed_path = (
            _project_root()
            / ".claude" / "skills" / "bridgebuilder-review"
            / "resources" / "lib" / "model-resolver.generated.ts"
        )
        if not committed_path.is_file():
            print(
                f"[BB-CODEGEN-MISSING] {committed_path} not committed",
                file=sys.stderr,
            )
            return 3
        committed = committed_path.read_text()
        if fresh != committed:
            print("[BB-CODEGEN-FAILED] generated TS differs from committed", file=sys.stderr)
            print("  regenerate via: python3 -m loa_cheval.codegen.emit_model_resolver_ts > " + str(committed_path), file=sys.stderr)
            return 3
        # Hash cross-check: provides ONE additional signal beyond byte-diff —
        # it catches the manual-edit-without-regenerate case (operator edits
        # canonical in-place; committed TS still has the OLD hash; fresh hash
        # of canonical differs).
        #
        # gp HIGH-2 (sprint-2D.c review) clarification: this check does NOT
        # defend against a tampered-canonical-with-matching-regen scenario in
        # the same PR — both files would be modified consistently and pass
        # both byte-diff and hash check. The defense for THAT scenario is
        # human review of the canonical change. The hash check is a
        # consistency guard, not a tamper detector.
        import re as _re
        _, canonical_path = _load_canonical()
        fresh_hash = _hash_source(canonical_path)
        m = _re.search(r"^// Source content hash:\s+([0-9a-f]{64})$", committed, _re.MULTILINE)
        if m is None:
            print(
                "[BB-CODEGEN-MISSING-HASH] committed TS lacks Source content hash header",
                file=sys.stderr,
            )
            return 3
        committed_hash = m.group(1)
        if committed_hash != fresh_hash:
            print(
                f"[BB-CODEGEN-HASH-DRIFT] committed hash {committed_hash} != fresh canonical hash {fresh_hash}",
                file=sys.stderr,
            )
            print(
                "  the canonical Python source has changed; regenerate the TS file.",
                file=sys.stderr,
            )
            return 3
        return 0

    if args.out:
        Path(args.out).write_text(fresh)
    else:
        sys.stdout.write(fresh)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
