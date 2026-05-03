"""
loa_cheval.audit_envelope — Python equivalent of audit-envelope.sh.

cycle-098 Sprint 1A foundation, extended in Sprint 1B with Ed25519 signing.

Same interface contract as the bash version:

    audit_emit(primitive_id, event_type, payload, log_path)
    audit_verify_chain(log_path) -> tuple[bool, str]
    audit_seal_chain(primitive_id, log_path)
    audit_trust_store_verify(trust_store_path) -> tuple[bool, str]  (Sprint 1B)

Sprint 1B: when LOA_AUDIT_SIGNING_KEY_ID is set, audit_emit signs the chain
input with Ed25519 and populates signature + signing_key_id. Verification is
performed automatically when entries carry signatures (LOA_AUDIT_VERIFY_SIGS=0
to opt out).

Behavior identity vs the bash adapter is enforced by integration tests
(tests/integration/audit-envelope-chain.bats,
tests/unit/audit-envelope-schema.bats,
tests/integration/audit-envelope-signing.bats).
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import stat
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional, Tuple, Union

from loa_cheval.jcs import canonicalize as jcs_canonicalize

PathLike = Union[str, Path]

# Schema version this writer emits. Bumped to 1.1.0 in Sprint 1B (additive).
DEFAULT_SCHEMA_VERSION = "1.1.0"

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


def _key_dir() -> Path:
    """Resolve the active key directory (LOA_AUDIT_KEY_DIR or default)."""
    return Path(
        os.environ.get(
            "LOA_AUDIT_KEY_DIR",
            str(Path.home() / ".config" / "loa" / "audit-keys"),
        )
    )


def _trust_store_path() -> Path:
    """Resolve the trust-store path (LOA_TRUST_STORE_FILE or default)."""
    default = _THIS.parent.parent.parent.parent / "grimoires" / "loa" / "trust-store.yaml"
    return Path(os.environ.get("LOA_TRUST_STORE_FILE", str(default)))


def _pinned_root_pubkey_path() -> Path:
    """Pinned root pubkey path (LOA_PINNED_ROOT_PUBKEY_PATH or default)."""
    default = _THIS.parent.parent.parent / "data" / "maintainer-root-pubkey.txt"
    return Path(os.environ.get("LOA_PINNED_ROOT_PUBKEY_PATH", str(default)))


def _read_password_from_env() -> Optional[bytes]:
    """
    Sprint 1B: support LOA_AUDIT_KEY_PASSWORD env var as a DEPRECATED fallback.
    Emits a stderr warning and scrubs the env var after reading.

    Operators should prefer --password-fd / --password-file (CLI surface) or
    pre-decrypt the key when calling the Python API.
    """
    pw = os.environ.get("LOA_AUDIT_KEY_PASSWORD")
    if pw is None:
        return None
    sys.stderr.write(
        "[audit-envelope] WARNING: LOA_AUDIT_KEY_PASSWORD env var is "
        "DEPRECATED (SKP-002). Use --password-fd or --password-file. "
        "Will be removed in v2.0.\n"
    )
    # Scrub.
    del os.environ["LOA_AUDIT_KEY_PASSWORD"]
    return pw.encode()


def _load_private_key(key_id: str, password: Optional[bytes] = None):
    """
    Load a writer's private key for signing. Required: cryptography package.
    Returns an Ed25519PrivateKey. Raises FileNotFoundError or ValueError on
    failure.
    """
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ed25519

    priv_path = _key_dir() / f"{key_id}.priv"
    if not priv_path.is_file():
        raise FileNotFoundError(f"private key not found: {priv_path}")
    st_mode = priv_path.stat().st_mode
    if st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise PermissionError(
            f"private key {priv_path} has too permissive mode "
            f"({oct(st_mode & 0o777)}); require 0600"
        )
    if password is None:
        password = _read_password_from_env()
    priv = serialization.load_pem_private_key(priv_path.read_bytes(), password=password)
    if not isinstance(priv, ed25519.Ed25519PrivateKey):
        raise ValueError(f"key at {priv_path} is not Ed25519")
    return priv


def _resolve_pubkey_pem(key_id: str) -> Optional[str]:
    """
    Resolve the PEM-encoded pubkey for <key_id>:
      1. Trust-store entry (when YAML + yaml package available)
      2. <key-dir>/<key_id>.pub (test/CI fallback)
    Returns the PEM string or None if unresolvable.
    """
    ts_path = _trust_store_path()
    if ts_path.is_file():
        try:
            import yaml
            with ts_path.open("r", encoding="utf-8") as f:
                doc = yaml.safe_load(f) or {}
            for entry in doc.get("keys") or []:
                if entry.get("writer_id") == key_id:
                    pem = entry.get("pubkey_pem")
                    if pem:
                        return pem
        except Exception:  # pragma: no cover — defensive
            pass
    # Local fallback.
    pub_path = _key_dir() / f"{key_id}.pub"
    if pub_path.is_file():
        return pub_path.read_text(encoding="utf-8")
    return None


def _verify_signature(pubkey_pem: str, canonical: bytes, sig_b64: str) -> bool:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.exceptions import InvalidSignature

    pub = serialization.load_pem_public_key(pubkey_pem.encode())
    if not isinstance(pub, ed25519.Ed25519PublicKey):
        return False
    try:
        sig = base64.b64decode(sig_b64, validate=True)
    except Exception:
        return False
    try:
        pub.verify(sig, canonical)
        return True
    except InvalidSignature:
        return False


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
    signing_key_id: Optional[str] = None,
    password: Optional[bytes] = None,
) -> dict:
    """
    Build a validated envelope and append it as a JSONL line to `log_path`.

    Sprint 1B: when `signing_key_id` is provided OR LOA_AUDIT_SIGNING_KEY_ID
    is set in the environment, the canonical chain-input is signed with Ed25519
    and signature + signing_key_id are added to the envelope.

    Args:
        primitive_id: One of L1..L7.
        event_type: Primitive-specific event name (e.g., "panel.bind").
        payload: dict — primitive-specific event payload.
        log_path: JSONL log file path.
        schema_version: Override the writer's schema version (rare).
        signing_key_id: Override LOA_AUDIT_SIGNING_KEY_ID env var.
        password: Optional bytes for decrypting the private key.

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

    # Sprint 1B: sign chain-input when signing key configured.
    kid = signing_key_id or os.environ.get("LOA_AUDIT_SIGNING_KEY_ID")
    if kid:
        priv = _load_private_key(kid, password=password)
        canonical = _chain_input_bytes(envelope)
        sig = priv.sign(canonical)
        envelope["signing_key_id"] = kid
        envelope["signature"] = base64.b64encode(sig).decode()

    _validate_envelope(envelope)

    # Append a single JSON line (no internal whitespace, terminated \n).
    line = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(line)
        f.write("\n")
    return envelope


def _read_trust_cutoff() -> Optional[str]:
    """
    Read trust_cutoff.default_strict_after from the active trust-store.

    Returns the ISO-8601 string or None when unset/missing/unreadable.
    F1 review remediation: post-cutoff entries require both signature
    AND signing_key_id (strip-attack defense).
    """
    ts_path = _trust_store_path()
    if not ts_path.is_file():
        return None
    try:
        import yaml
        with ts_path.open("r", encoding="utf-8") as f:
            doc = yaml.safe_load(f) or {}
        cutoff = ((doc.get("trust_cutoff") or {}).get("default_strict_after") or "").strip()
        return cutoff or None
    except Exception:  # pragma: no cover — defensive
        return None


def _ts_ge_cutoff(ts_utc: str, cutoff: Optional[str]) -> bool:
    """
    F1: True if ts_utc >= cutoff (post-cutoff). Empty cutoff => False
    (no cutoff configured = grandfather all). Lexicographic ISO-8601 UTC
    comparison.
    """
    if not cutoff or not ts_utc:
        return False
    return ts_utc >= cutoff


def audit_verify_chain(log_path: PathLike) -> Tuple[bool, str]:
    """
    Walk `log_path` line-by-line; verify each entry's prev_hash matches the
    SHA-256 of the prior entry's canonical chain-input. First entry must have
    prev_hash == "GENESIS".

    Sprint 1B: when an entry carries `signature` + `signing_key_id`, the
    Ed25519 signature is also verified against the pubkey resolved via the
    trust-store (or local <key-dir>/<key_id>.pub fallback). Set
    LOA_AUDIT_VERIFY_SIGS=0 to skip signature verification (e.g., when
    migrating legacy un-signed logs).

    F1 (review remediation): for entries with ts_utc >= trust_cutoff, BOTH
    signature AND signing_key_id are REQUIRED. Stripping either is a
    downgrade attack and produces [STRIP-ATTACK-DETECTED]. Pre-cutoff
    entries are grandfathered per IMP-002.

    Returns (ok, message). On failure, message includes line number + reason.
    """
    log_path = Path(log_path)
    if not log_path.exists():
        return False, f"file not found: {log_path}"

    verify_sigs = os.environ.get("LOA_AUDIT_VERIFY_SIGS", "1") != "0"
    cutoff = _read_trust_cutoff()

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
            # Sprint 1B signature verification.
            if verify_sigs:
                sig_b64 = env.get("signature")
                kid = env.get("signing_key_id")
                ts_utc = env.get("ts_utc", "")

                # F1: strict requirement post-trust-cutoff.
                if _ts_ge_cutoff(ts_utc, cutoff):
                    if not sig_b64 or not kid:
                        sig_state = "present" if sig_b64 else "MISSING"
                        kid_state = "present" if kid else "MISSING"
                        return False, (
                            f"BROKEN line {lineno}: [STRIP-ATTACK-DETECTED] "
                            f"signature required post-cutoff "
                            f"(cutoff={cutoff}, ts={ts_utc}, "
                            f"sig={sig_state}, kid={kid_state})"
                        )

                if sig_b64 and kid:
                    pubkey_pem = _resolve_pubkey_pem(kid)
                    if pubkey_pem is None:
                        return False, (
                            f"BROKEN line {lineno}: cannot resolve public key "
                            f"for signing_key_id={kid}"
                        )
                    canonical = _chain_input_bytes(env)
                    if not _verify_signature(pubkey_pem, canonical, sig_b64):
                        return False, (
                            f"BROKEN line {lineno}: signature verification "
                            f"failed for signing_key_id={kid}"
                        )
            expected_prev = _sha256_hex(_chain_input_bytes(env))
            count += 1
    return True, f"OK {count} entries"


def audit_trust_store_verify(
    trust_store_path: Optional[PathLike] = None,
) -> Tuple[bool, str]:
    """
    Verify the trust-store's `root_signature` against the pinned root pubkey.

    Sprint 1B per SDD §1.9.3.1: trust-store updates require maintainer offline
    root key signature. This function delegates to audit-signing-helper.py
    (R15: behavior identity).

    Returns (ok, message).
    """
    import subprocess

    ts = Path(trust_store_path) if trust_store_path else _trust_store_path()
    pinned = _pinned_root_pubkey_path()
    helper = (
        _THIS.parent.parent.parent  # .claude/
        / "scripts"
        / "lib"
        / "audit-signing-helper.py"
    )
    if not helper.is_file():
        return False, f"signing helper not found: {helper}"
    proc = subprocess.run(
        ["python3", str(helper), "trust-store-verify",
         "--pinned-pubkey", str(pinned),
         "--trust-store", str(ts)],
        capture_output=True, text=True,
    )
    if proc.returncode == 0:
        return True, "trust-store verified"
    return False, proc.stderr.strip() or f"trust-store verification failed (rc={proc.returncode})"


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
    "audit_trust_store_verify",
    "DEFAULT_SCHEMA_VERSION",
]
