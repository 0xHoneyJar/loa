"""emit_endpoint_validator_ts — render the TS port of the cycle-099 endpoint
validator from the canonical Python source via Jinja2.

Per cycle-099 SDD §1.9.1 IMP-002, this module is the first build step of the
Bridgebuilder skill: it reads the constants embedded in
.claude/scripts/lib/endpoint-validator.py (regex patterns, blocked IPv6
networks, control-byte sets) and substitutes them into
.claude/scripts/lib/codegen/endpoint-validator.ts.j2 to produce
.claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts.

Determinism: source-content hash is recorded in the generated header. CI runs
this module + diffs the committed output → drift = PR fail.

Usage:
    python3 -m loa_cheval.codegen.emit_endpoint_validator_ts > out.ts
    python3 -m loa_cheval.codegen.emit_endpoint_validator_ts --check  # exit 3 on drift
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
    #   <root>/.claude/adapters/loa_cheval/codegen/emit_endpoint_validator_ts.py
    # parents[0] = codegen
    # parents[1] = loa_cheval
    # parents[2] = adapters
    # parents[3] = .claude
    # parents[4] = <root>
    return Path(__file__).resolve().parents[4]


def _load_canonical() -> Any:
    """Load .claude/scripts/lib/endpoint-validator.py via spec_loader. The
    file uses dashes which Python can't import normally.

    The module must be registered in sys.modules BEFORE exec_module so the
    dataclass decorator (used by ValidationResult) can resolve its own
    __module__ via sys.modules during introspection. Without this step
    Python 3.13 raises AttributeError on the first @dataclass.
    """
    canonical_path = (
        _project_root() / ".claude" / "scripts" / "lib" / "endpoint-validator.py"
    )
    if not canonical_path.is_file():
        raise FileNotFoundError(f"canonical not found: {canonical_path}")
    module_name = "endpoint_validator_canonical"
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
    the TS file produces a header mismatch the drift gate will catch."""
    return hashlib.sha256(canonical_path.read_bytes()).hexdigest()


def _build_context(canonical: Any, source_hash: str) -> dict[str, Any]:
    """Extract constants from the canonical and assemble the Jinja2 context."""
    blocked_ipv6_networks = [str(net) for net in canonical._BLOCKED_IPV6_NETWORKS]
    path_forbidden_bytes = list(canonical._PATH_FORBIDDEN_BYTES)
    path_control_chars = list(canonical._PATH_CONTROL_CHARS)
    path_traversal_re_source = canonical._PATH_TRAVERSAL_RE.pattern
    # sprint-1E.c.1 review: forbidden chars in raw URL authority. Sorted by
    # codepoint for deterministic ordering across Python releases.
    authority_forbidden_chars = sorted(
        canonical._AUTHORITY_FORBIDDEN_CHARS, key=ord
    )
    return {
        "source_hash": source_hash,
        "generator_version": GENERATOR_VERSION,
        "blocked_ipv6_networks": blocked_ipv6_networks,
        "path_forbidden_bytes": path_forbidden_bytes,
        "path_control_chars": path_control_chars,
        "path_traversal_re_source": path_traversal_re_source,
        "authority_forbidden_chars": authority_forbidden_chars,
    }


def _ts_escape_cp(s: str) -> str:
    """Emit a TS string literal escape for a single character (cypherpunk
    MEDIUM 2). Handles non-BMP codepoints via the `\\u{XXXXX}` form so a
    future addition of e.g. U+E0001 doesn't silently corrupt the TS output.

    BMP (≤ U+FFFF):   `"\\u00ad"`        (4-digit form)
    Non-BMP:           `"\\u{e0001}"`     (variable-length brace form, ES2015)
    """
    if not isinstance(s, str) or len(s) != 1:
        # Multi-char or non-string — emit a JSON-quoted literal as fallback.
        import json
        return json.dumps(s)
    cp = ord(s)
    if cp <= 0xFFFF:
        return f'"\\u{cp:04x}"'
    return f'"\\u{{{cp:x}}}"'


def _render(context: dict[str, Any]) -> str:
    """Render the Jinja2 template."""
    from jinja2 import Environment, FileSystemLoader, StrictUndefined

    template_dir = _project_root() / ".claude" / "scripts" / "lib" / "codegen"
    env = Environment(
        loader=FileSystemLoader(str(template_dir)),
        keep_trailing_newline=True,
        undefined=StrictUndefined,
        # Autoescape would HTML-escape our TS source; we're emitting plain
        # text, so disable it. Jinja2's `tojson` filter is still safe-by-
        # construction (escapes JSON-significant chars).
        autoescape=False,
    )
    # Custom filter: ord() so the template can compute hex code points for
    # `\uXXXX` escapes in the TS literal output. Jinja2 doesn't ship `ord` by
    # default for arbitrary strings; we add a per-character variant.
    env.filters["ord"] = lambda s: ord(s) if isinstance(s, str) and len(s) == 1 else 0
    # ts_escape_cp emits a TS string literal for a single character, surrogate-
    # aware. Mandatory for substituting characters into TS source — cypherpunk
    # MEDIUM 2 found that bare `'%04x'` would silently corrupt non-BMP chars.
    env.filters["ts_escape_cp"] = _ts_escape_cp
    template = env.get_template("endpoint-validator.ts.j2")
    return template.render(**context)


def emit() -> str:
    """Run the full pipeline and return the rendered TS as a string."""
    canonical, canonical_path = _load_canonical()
    source_hash = _hash_source(canonical_path)
    context = _build_context(canonical, source_hash)
    return _render(context)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="emit_endpoint_validator_ts",
        description=(
            "Render endpoint-validator.generated.ts from the canonical "
            "Python source + Jinja2 template."
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
            "Write to this path instead of stdout. Default: stdout (callers "
            "redirect; CI relies on stdout for diff)."
        ),
    )
    args = parser.parse_args(argv)

    fresh = emit()

    if args.check:
        committed_path = (
            _project_root()
            / ".claude"
            / "skills"
            / "bridgebuilder-review"
            / "resources"
            / "lib"
            / "endpoint-validator.generated.ts"
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
            print("  regenerate via: python3 -m loa_cheval.codegen.emit_endpoint_validator_ts > " + str(committed_path), file=sys.stderr)
            return 3
        # gp MEDIUM remediation: also cross-check the embedded source-hash
        # header against a fresh hash of the canonical Python file. This
        # catches a tampered-but-recompilable scenario where a malicious
        # contributor edits the canonical AND regenerates the TS in lockstep
        # — the hash would still be deterministic-from-canonical, but the
        # explicit cross-check forces operator review of any canonical edit.
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
