"""
loa_cheval.audit_envelope — Python equivalent of audit-envelope.sh.

cycle-098 Sprint 1A foundation. Same interface contract as the bash version:

    audit_emit(primitive_id, event_type, payload, log_path)
    audit_verify_chain(log_path) -> tuple[bool, str]
    audit_seal_chain(primitive_id, log_path)

Sprint 1B will add Ed25519 signing on emit + signature verification in
verify_chain. The Python adapter is the canonical reference where the schema
spec is ambiguous; the bash adapter is required to match its byte output.

Behavior identity vs the bash adapter is enforced by integration tests
(tests/integration/audit-envelope-chain.bats and
tests/unit/audit-envelope-schema.bats).
"""

from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Tuple, Union

from loa_cheval.jcs import canonicalize as jcs_canonicalize

PathLike = Union[str, Path]

# Schema version this writer emits. Bumped by major on breaking schema change.
DEFAULT_SCHEMA_VERSION = "1.0.0"

# Resolve the schema relative to this file (.claude/adapters/loa_cheval/) ->
# .claude/data/trajectory-schemas/.
_THIS = Path(__file__).resolve()
_SCHEMA_PATH = (
    _THIS.parent.parent.parent  # .claude/
    / "data"
    / "trajectory-schemas"
    / "agent-network-envelope.schema.json"
)


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------


def _now_iso8601() -> str:
    """Microsecond-precision UTC ISO-8601 timestamp (Z-suffixed)."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def _chain_input_bytes(envelope: dict) -> bytes:
    """
    Compute the canonical-JSON bytes used for prev_hash + signature.

    Excludes `signature` and `signing_key_id` per SDD §1.4.1.
    """
    stripped = {k: v for k, v in envelope.items() if k not in {"signature", "signing_key_id"}}
    return jcs_canonicalize(stripped)


def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _compute_prev_hash(log_path: Path) -> str:
    """
    Read the last non-marker JSON line from `log_path` and return the SHA-256
    hex digest of its canonical chain-input. 'GENESIS' if the file is empty.
    """
    if not log_path.exists() or log_path.stat().st_size == 0:
        return "GENESIS"

    last: str | None = None
    with log_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("["):
                continue
            last = line
    if last is None:
        return "GENESIS"

    last_env = json.loads(last)
    return _sha256_hex(_chain_input_bytes(last_env))


def _validate_envelope(envelope: dict) -> None:
    """
    Validate envelope against the JSON schema. Raises ValueError on failure.

    Uses jsonschema (R15: behavior identical between adapters).
    """
    try:
        import jsonschema
    except ImportError as exc:  # pragma: no cover — defensive
        raise RuntimeError(
            "jsonschema not installed. pip install jsonschema"
        ) from exc

    with _SCHEMA_PATH.open("r", encoding="utf-8") as f:
        schema = json.load(f)

    try:
        jsonschema.validate(envelope, schema)
    except jsonschema.ValidationError as exc:
        raise ValueError(f"envelope failed schema validation: {exc.message}") from exc


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------


def audit_emit(
    primitive_id: str,
    event_type: str,
    payload: dict,
    log_path: PathLike,
    *,
    schema_version: str = DEFAULT_SCHEMA_VERSION,
) -> dict:
    """
    Build a validated envelope and append it as a JSONL line to `log_path`.

    TODO(Sprint 1B): Sign the chain-input bytes with Ed25519. Until then,
    the optional `signature` and `signing_key_id` are omitted (schema-permitted
    in Sprint 1A; required in 1B).

    Args:
        primitive_id: One of L1..L7.
        event_type: Primitive-specific event name (e.g., "panel.bind").
        payload: dict — primitive-specific event payload.
        log_path: JSONL log file path.
        schema_version: Override the writer's schema version (rare).

    Returns:
        The envelope dict that was appended.
    """
    if not isinstance(payload, dict):
        raise TypeError("payload must be a dict")

    log_path = Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    envelope = {
        "schema_version": schema_version,
        "primitive_id": primitive_id,
        "event_type": event_type,
        "ts_utc": _now_iso8601(),
        "prev_hash": _compute_prev_hash(log_path),
        "payload": payload,
        "redaction_applied": None,
    }

    _validate_envelope(envelope)

    # Append a single JSON line (no internal whitespace, terminated \n).
    line = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(line)
        f.write("\n")
    return envelope


def audit_verify_chain(log_path: PathLike) -> Tuple[bool, str]:
    """
    Walk `log_path` line-by-line; verify each entry's prev_hash matches the
    SHA-256 of the prior entry's canonical chain-input. First entry must have
    prev_hash == "GENESIS".

    Returns (ok, message). On failure, message includes line number + reason.

    TODO(Sprint 1B): also verify Ed25519 signature against signing_key_id pubkey.
    """
    log_path = Path(log_path)
    if not log_path.exists():
        return False, f"file not found: {log_path}"

    expected_prev = "GENESIS"
    count = 0
    with log_path.open("r", encoding="utf-8") as f:
        for lineno, raw in enumerate(f, start=1):
            line = raw.rstrip("\n")
            if not line or line.startswith("["):
                continue
            try:
                env = json.loads(line)
            except json.JSONDecodeError as exc:
                return False, f"BROKEN line {lineno}: invalid JSON ({exc})"
            actual_prev = env.get("prev_hash")
            if actual_prev is None:
                return False, f"BROKEN line {lineno}: missing prev_hash"
            if actual_prev != expected_prev:
                return False, (
                    f"BROKEN line {lineno}: prev_hash mismatch "
                    f"(got {actual_prev}, expected {expected_prev})"
                )
            expected_prev = _sha256_hex(_chain_input_bytes(env))
            count += 1
    return True, f"OK {count} entries"


def audit_seal_chain(primitive_id: str, log_path: PathLike) -> None:
    """
    Append a `[<PRIMITIVE>-DISABLED]` marker indicating the primitive has been
    sealed (e.g., uninstalled, decommissioned). The marker is NOT a JSON
    envelope; chain walks skip it.
    """
    log_path = Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(f"[{primitive_id}-DISABLED]\n")


__all__ = [
    "audit_emit",
    "audit_verify_chain",
    "audit_seal_chain",
    "DEFAULT_SCHEMA_VERSION",
]
