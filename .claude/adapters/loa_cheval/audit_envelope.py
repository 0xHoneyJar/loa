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
import contextlib
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional, Tuple, Union

from loa_cheval.jcs import canonicalize as jcs_canonicalize

try:
    import fcntl  # POSIX-only; matches bash adapter's flock requirement (CC-3)
    _HAS_FCNTL = True
except ImportError:  # pragma: no cover — Windows fallback
    _HAS_FCNTL = False

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


def _strict_verify_enabled(verify_for_merge: bool = False) -> bool:
    """True when verification is running as a merge gate."""
    return verify_for_merge or os.environ.get("LOA_AUDIT_STRICT_VERIFY", "0") == "1"


def _resolve_pubkey_pem(
    key_id: str, *, allow_local_fallback: bool = True, ts_utc: Optional[str] = None,
    trusted_document: Optional[dict] = None,
) -> Optional[str]:
    """
    Resolve the PEM-encoded pubkey for <key_id>:
      1. Trust-store entry (when YAML + yaml package available)
      2. <key-dir>/<key_id>.pub (explicit bootstrap stores only, never strict)
    Returns the PEM string or None if unresolvable.
    """
    # Never use a claimed writer id as an arbitrary filesystem path.
    if not isinstance(key_id, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", key_id):
        return None
    if trusted_document is not None:
        status, doc = "VERIFIED", trusted_document
    else:
        status, doc = _trust_store_snapshot()
    if status == "INVALID":
        return None
    if doc is not None:
        try:
            for revocation in doc.get("revocations") or []:
                if revocation.get("writer_id") == key_id:
                    if ts_utc is None or _parse_timestamp(ts_utc) >= _parse_timestamp(
                        revocation.get("revoked_at")
                    ):
                        return None
            matches = [
                entry for entry in doc.get("keys") or []
                if entry.get("writer_id") == key_id
            ]
            if status == "VERIFIED":
                # A signed store is authoritative even when the lookup misses.
                # Ambiguous bindings, malformed keys, and revoked writers fail closed.
                if len(matches) != 1:
                    return None
                pem = matches[0].get("pubkey_pem")
                return pem if isinstance(pem, str) and pem.strip() else None
        except Exception:  # pragma: no cover — defensive
            return None
    # ATK-3: verify-for-merge must not trust producer-writable local pubkeys.
    if not allow_local_fallback:
        return None
    # Local fallback.
    pub_path = _key_dir() / f"{key_id}.pub"
    if pub_path.is_file():
        return pub_path.read_text(encoding="utf-8")
    return None


def _verify_signature(pubkey_pem: str, canonical: bytes, sig_b64: str) -> bool:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.exceptions import InvalidSignature

    try:
        pub = serialization.load_pem_public_key(pubkey_pem.encode())
    except (TypeError, ValueError):
        return False
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


@contextlib.contextmanager
def _acquire_log_lock(log_path: Path, timeout: float = 10.0):
    """
    Acquire an exclusive flock on `<log_path>.lock` for the entire
    compute-prev-hash → sign → validate → append sequence.

    Mirrors bash `audit_emit` flock-on-emit pattern (issue #689 / CC-3) so
    concurrent bash + Python writers serialize on the same file lock. Without
    this, racing tail-reads + appends produce missing entries or a broken
    chain — issue surfaced by Sprint 1 audit MED-1.

    Raises TimeoutError after `timeout` seconds of contention.
    Non-blocking + sleep-loop is portable across kernels with deterministic
    bounds; matches bash's `flock -w 10` semantics.
    """
    if not _HAS_FCNTL:
        raise RuntimeError(
            "audit_emit requires fcntl for atomic chain writes (CC-3). "
            "Python on this platform lacks fcntl support."
        )
    lock_path = Path(f"{log_path}.lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    if not lock_path.exists():
        lock_path.touch()

    deadline = time.monotonic() + timeout
    fd = open(lock_path, "w")
    try:
        while True:
            try:
                fcntl.flock(fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(
                        f"audit_emit: failed to acquire lock on {lock_path} "
                        f"(timeout {timeout}s)"
                    )
                time.sleep(0.01)
        try:
            yield
        finally:
            try:
                fcntl.flock(fd.fileno(), fcntl.LOCK_UN)
            except OSError:  # pragma: no cover — defensive
                pass
    finally:
        fd.close()


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

    # Issue #690 (Sprint 1.5): auto-verify trust-store before any write.
    # BOOTSTRAP-PENDING + VERIFIED permit; INVALID raises [TRUST-STORE-INVALID].
    _check_trust_store()

    log_path = Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    # Issue #689 (Sprint 1.5): acquire flock on <log_path>.lock for the entire
    # compute-prev-hash → sign → validate → append sequence. Bash adapter does
    # this post-Sprint-1 F3 (CC-3); without parity, mixed bash + Python writers
    # race. Sprint 2's L2 reconciliation cron is the first cross-adapter
    # writer of the audit envelope.
    with _acquire_log_lock(log_path):
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


# -----------------------------------------------------------------------------
# Cache authentication by policy and pinned-root paths/content. Retain the
# parsed document from those exact bytes for key and cutoff consumers.
# -----------------------------------------------------------------------------
_TRUST_STORE_CACHE: dict = {"path": None, "key": None, "status": None, "document": None}


def _trust_store_snapshot() -> Tuple[str, Optional[dict]]:
    """
    Return the active trust-store's status and its authenticated document.

    BOOTSTRAP-PENDING graceful fallback: empty signature + empty keys[] +
    empty revocations[] = the operator has not yet bootstrapped a signed
    trust-store; reads/writes are permitted so cycle-098 can install
    incrementally without requiring the maintainer-offline-root-key ceremony.

    VERIFIED: trust-store has a populated signature OR populated keys/
    revocations AND the root_signature verifies against the pinned root
    pubkey.

    INVALID: trust-store has populated keys/revocations but the
    root_signature does not verify (or is missing).

    Both policy and pinned root are read once per call. Their paths/content
    identify the cache entry; authentication uses those same snapshots.
    """
    ts_path = _trust_store_path()

    # No trust-store file → BOOTSTRAP-PENDING (cycle-098 install-time default).
    if not ts_path.is_file():
        return "BOOTSTRAP-PENDING", None

    try:
        raw = ts_path.read_bytes()
    except OSError:
        return "INVALID", None
    # Detect BOOTSTRAP-PENDING.
    bootstrap_pending = False
    try:
        import yaml  # noqa: PLC0415
        doc = yaml.safe_load(raw) or {}
        sig = ((doc.get("root_signature") or {}).get("signature") or "").strip()
        keys = doc.get("keys") or []
        revs = doc.get("revocations") or []
        if not sig and not keys and not revs:
            bootstrap_pending = True
    except Exception:
        # A present but unreadable/malformed store is not an empty bootstrap store.
        return "INVALID", None

    pin_path = _pinned_root_pubkey_path()
    pin_raw = b""
    if not bootstrap_pending:
        try:
            pin_raw = pin_path.read_bytes()
        except OSError:
            return "INVALID", None
    cache_key = (
        hashlib.sha256(raw).hexdigest(), str(pin_path),
        hashlib.sha256(pin_raw).hexdigest(),
    )
    cache = _TRUST_STORE_CACHE
    if (
        cache["path"] == str(ts_path)
        and cache["key"] == cache_key
        and cache["status"] is not None
    ):
        return cache["status"], cache["document"]

    if bootstrap_pending:
        status = "BOOTSTRAP-PENDING"
    else:
        # Authenticate the exact bytes that were parsed. Later key/cutoff
        # consumers use this document rather than reopening a mutable path.
        with tempfile.TemporaryDirectory(prefix="loa-audit-policy-") as directory:
            snapshot = Path(directory) / "trust-store.yaml"
            snapshot.write_bytes(raw)
            pin_snapshot = Path(directory) / "root.pub"
            pin_snapshot.write_bytes(pin_raw)
            ok, _msg = _verify_trust_store_files(snapshot, pin_snapshot)
        status = "VERIFIED" if ok else "INVALID"

    cache["path"] = str(ts_path)
    cache["key"] = cache_key
    cache["status"] = status
    cache["document"] = doc
    return status, doc


def _trust_store_status() -> str:
    return _trust_store_snapshot()[0]


def _check_trust_store(*, strict_verify: bool = False) -> Tuple[str, Optional[dict]]:
    """
    Gate function called at top of audit_emit + audit_verify_chain.
    Raises RuntimeError with [TRUST-STORE-INVALID] on tampered trust-stores.
    """
    status, doc = _trust_store_snapshot()
    if status == "VERIFIED":
        return status, doc
    # ATK-3: BOOTSTRAP-PENDING is acceptable for install-time writes, but a
    # merge verifier must fail closed until the trust root is signed.
    if status == "BOOTSTRAP-PENDING" and not strict_verify:
        return status, doc
    if status == "BOOTSTRAP-PENDING":
        raise RuntimeError(
            "[TRUST-STORE-BOOTSTRAP-PENDING] trust-store is not signed; "
            "strict audit verification refuses BOOTSTRAP-PENDING (ATK-3)"
        )
    raise RuntimeError(
        "[TRUST-STORE-INVALID] trust-store root_signature does NOT verify "
        "against pinned root pubkey; refusing all writes/reads (issue #690)"
    )


def _read_trust_cutoff(
    *, strict_verify: bool = False, trusted_document: Optional[dict] = None
) -> Optional[str]:
    """
    Read trust_cutoff.default_strict_after from the active trust-store.

    Returns the ISO-8601 string or None when unset in non-strict mode.
    The trust-store gate already rejects missing/unreadable stores in strict
    mode (ATK-4); this checks the root-signed cutoff policy itself.
    F1 review remediation: post-cutoff entries require both signature
    AND signing_key_id (strip-attack defense).
    """
    ts_path = _trust_store_path()
    if trusted_document is None and not ts_path.is_file():
        return None
    try:
        if trusted_document is not None:
            doc = trusted_document
        else:
            import yaml
            with ts_path.open("r", encoding="utf-8") as f:
                doc = yaml.safe_load(f) or {}
        cutoff = ((doc.get("trust_cutoff") or {}).get("default_strict_after") or "").strip()
        if cutoff:
            parsed = _parse_timestamp(cutoff)
            if strict_verify and parsed > datetime.now(timezone.utc):
                raise ValueError("cutoff is in the future")
        elif strict_verify:
            raise ValueError("cutoff is empty")
        return cutoff or None
    except Exception as exc:
        raise RuntimeError(
            "[TRUST-CUTOFF-INVALID] require a valid UTC cutoff; strict "
            "verification requires a nonempty cutoff already in effect"
        ) from exc


def _parse_timestamp(value: str) -> datetime:
    """Parse the envelope's UTC timestamp without lexicographic fraction bugs."""
    if not isinstance(value, str) or not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z", value
    ):
        raise ValueError("expected ISO-8601 UTC timestamp")
    return datetime.fromisoformat(value[:-1] + "+00:00")


def _ts_ge_cutoff(ts_utc: str, cutoff: Optional[str]) -> bool:
    """
    F1: True if ts_utc >= cutoff (post-cutoff). Empty cutoff => False
    (no cutoff configured = grandfather all). Compare instants so fractional
    seconds cannot move a post-cutoff entry into grandfathered history.
    """
    if not cutoff or not ts_utc:
        return False
    return _parse_timestamp(ts_utc) >= _parse_timestamp(cutoff)


def audit_verify_chain(log_path: PathLike, *, verify_for_merge: bool = False) -> Tuple[bool, str]:
    """
    Walk `log_path` line-by-line; verify each entry's prev_hash matches the
    SHA-256 of the prior entry's canonical chain-input. First entry must have
    prev_hash == "GENESIS".

    Sprint 1B: when an entry carries `signature` + `signing_key_id`, the
    Ed25519 signature is also verified against the pubkey resolved via the
    trust-store (or local <key-dir>/<key_id>.pub fallback). Set
    LOA_AUDIT_VERIFY_SIGS=0 to skip signature verification (e.g., when
    migrating legacy un-signed logs). Strict verification always verifies
    signatures and requires an effective root-signed cutoff.

    F1 (review remediation): for entries with ts_utc >= trust_cutoff, BOTH
    signature AND signing_key_id are REQUIRED. Stripping either is a
    downgrade attack and produces [STRIP-ATTACK-DETECTED]. Pre-cutoff
    entries are grandfathered per IMP-002.

    Returns (ok, message). On failure, message includes line number + reason.
    """
    log_path = Path(log_path)
    if not log_path.exists():
        return False, f"file not found: {log_path}"

    strict_verify = _strict_verify_enabled(verify_for_merge)

    # Issue #690 (Sprint 1.5): auto-verify trust-store before chain walk.
    try:
        store_status, trusted_document = _check_trust_store(strict_verify=strict_verify)
    except RuntimeError as exc:
        return False, str(exc)

    verify_sigs = strict_verify or os.environ.get("LOA_AUDIT_VERIFY_SIGS", "1") != "0"
    try:
        cutoff = _read_trust_cutoff(
            strict_verify=strict_verify, trusted_document=trusted_document
        )
    except RuntimeError as exc:
        return False, str(exc)

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
            if not isinstance(env, dict):
                return False, f"BROKEN line {lineno}: expected JSON object"
            actual_prev = env.get("prev_hash")
            if actual_prev is None:
                return False, f"BROKEN line {lineno}: missing prev_hash"
            if actual_prev != expected_prev:
                return False, (
                    f"BROKEN line {lineno}: prev_hash mismatch "
                    f"(got {actual_prev}, expected {expected_prev})"
                )
            # Removing/replacing the store with a bootstrap document must not
            # authorize signed history, even with the legacy signature toggle off.
            if env.get("signature") or env.get("signing_key_id"):
                if store_status != "VERIFIED":
                    return False, f"BROKEN line {lineno}: [TRUST-STORE-BOOTSTRAP-PENDING] signed history requires a verified store"
            # Sprint 1B signature verification.
            if verify_sigs:
                sig_b64 = env.get("signature")
                kid = env.get("signing_key_id")
                ts_utc = env.get("ts_utc", "")
                if strict_verify or cutoff or sig_b64 or kid:
                    try:
                        _parse_timestamp(ts_utc)
                    except ValueError:
                        return False, f"BROKEN line {lineno}: invalid ts_utc"

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
                    pubkey_pem = _resolve_pubkey_pem(
                        kid,
                        allow_local_fallback=not strict_verify,
                        ts_utc=ts_utc,
                        trusted_document=trusted_document,
                    )
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
    ts = Path(trust_store_path) if trust_store_path else _trust_store_path()
    return _verify_trust_store_files(ts, _pinned_root_pubkey_path())


def _verify_trust_store_files(ts: Path, pinned: Path) -> Tuple[bool, str]:
    import subprocess

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
