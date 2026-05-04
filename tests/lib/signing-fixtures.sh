#!/usr/bin/env bash
# =============================================================================
# tests/lib/signing-fixtures.sh — shared signed-mode test setup
#
# cycle-098 Sprint H1 (closes #706 + #713 + similar follow-ups). Consolidates
# the per-test ephemeral-Ed25519-keypair + trust-store + env-var dance that
# was duplicated across audit-envelope-signing.bats, audit-envelope-strip-
# attack.bats, audit-envelope-bootstrap.bats, panel-audit-envelope.bats.
#
# Public API (call inside `setup()` / `teardown()`):
#   signing_fixtures_setup [--strict|--bootstrap] [--key-id <id>] [--cutoff <iso>]
#   signing_fixtures_teardown
#
# Modes:
#   --strict    (default) Trust-store cutoff in the past + pubkey REGISTERED
#               in `keys[]`. Sets LOA_AUDIT_VERIFY_SIGS=1. The full happy
#               path: audit_emit signs, audit_verify_chain validates.
#   --bootstrap Trust-store empty `keys[]` (BOOTSTRAP-PENDING). audit_emit
#               accepts unsigned writes. Used for tests that exercise the
#               pre-bootstrap operator path.
#
# Variables exported to the test (via `export` so subshells inherit):
#   TEST_DIR        — mktemp dir; teardown removes it
#   KEY_DIR         — mode 0700; contains <key_id>.priv (0600) + <key_id>.pub
#   LOA_AUDIT_KEY_DIR
#   LOA_AUDIT_SIGNING_KEY_ID
#   LOA_TRUST_STORE_FILE
#   LOA_AUDIT_VERIFY_SIGS  (1 in --strict mode; unset in --bootstrap)
#
# Variables exposed (no export — caller can still use them inside its own
# setup() and they will be set in the test's shell scope):
#   _SIGN_FIX_KEY_ID, _SIGN_FIX_PUBKEY_PEM
#
# Skips the test (via `skip`) when prerequisites are missing:
#   - audit-envelope.sh
#   - python3 with cryptography module
#
# Idempotent: calling setup twice in a single test (or after teardown) is fine.
# =============================================================================

if [[ "${_LOA_SIGNING_FIXTURES_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_SIGNING_FIXTURES_SOURCED=1

# -----------------------------------------------------------------------------
# _sign_fix_repo_root — resolve the repo root from BATS_TEST_FILENAME or
# BATS_TEST_DIRNAME so callers don't have to compute it themselves.
# -----------------------------------------------------------------------------
_sign_fix_repo_root() {
    if [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then
        ( cd "${BATS_TEST_DIRNAME}/../.." && pwd )
    elif [[ -n "${BATS_TEST_FILENAME:-}" ]]; then
        ( cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd )
    else
        # Fallback: assume cwd is repo root (allowed when sourced manually).
        pwd
    fi
}

# -----------------------------------------------------------------------------
# signing_fixtures_setup [--strict|--bootstrap] [--key-id <id>] [--cutoff <iso>]
# -----------------------------------------------------------------------------
signing_fixtures_setup() {
    local mode="strict"
    local key_id="test-writer"
    local cutoff="2020-01-01T00:00:00Z"
    while (( "$#" )); do
        case "$1" in
            --strict)    mode="strict"; shift ;;
            --bootstrap) mode="bootstrap"; shift ;;
            --key-id)    key_id="$2"; shift 2 ;;
            --cutoff)    cutoff="$2"; shift 2 ;;
            *) echo "signing_fixtures_setup: unknown arg $1" >&2; return 1 ;;
        esac
    done

    local repo_root
    repo_root="$(_sign_fix_repo_root)"
    local audit_envelope="${repo_root}/.claude/scripts/audit-envelope.sh"
    if [[ ! -f "$audit_envelope" ]]; then
        skip "audit-envelope.sh not present"
    fi
    if ! python3 -c "import cryptography" 2>/dev/null; then
        skip "python cryptography not installed"
    fi

    TEST_DIR="$(mktemp -d)"
    KEY_DIR="${TEST_DIR}/audit-keys"
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"

    # Generate ephemeral Ed25519 keypair via Python (matches Sprint 1B helper).
    python3 - "$KEY_DIR" "$key_id" <<'PY'
import sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

key_dir = Path(sys.argv[1])
key_id  = sys.argv[2]
priv = ed25519.Ed25519PrivateKey.generate()
priv_bytes = priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)
pub_bytes = priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)
priv_path = key_dir / f"{key_id}.priv"
pub_path  = key_dir / f"{key_id}.pub"
priv_path.write_bytes(priv_bytes)
priv_path.chmod(0o600)
pub_path.write_bytes(pub_bytes)
PY

    _SIGN_FIX_KEY_ID="$key_id"
    _SIGN_FIX_PUBKEY_PEM="$(cat "${KEY_DIR}/${key_id}.pub")"

    # Build the trust-store. Both modes use BOOTSTRAP-PENDING shape (empty
    # keys[] + revocations[] + root_signature) so _audit_check_trust_store
    # permits writes without requiring a properly-signed root pubkey. Pubkey
    # resolution for verification falls through to <KEY_DIR>/<key_id>.pub
    # (the documented test path in audit-envelope.sh:311). The two modes
    # differ only in the trust_cutoff + LOA_AUDIT_VERIFY_SIGS:
    #   --strict   : cutoff in past, VERIFY_SIGS=1 → post-cutoff strip-attack
    #                gate active (signature + signing_key_id REQUIRED on emit;
    #                audit_verify_chain validates signatures on read).
    #   --bootstrap: cutoff far in future, VERIFY_SIGS unset → unsigned writes
    #                permitted (operator-bootstrap path).
    LOA_TRUST_STORE_FILE="${TEST_DIR}/trust-store.yaml"
    if [[ "$mode" == "strict" ]]; then
        cat > "$LOA_TRUST_STORE_FILE" <<EOF
schema_version: "1.0"
root_signature:
  algorithm: ed25519
  signer_pubkey: ""
  signed_at: ""
  signature: ""
keys: []
revocations: []
trust_cutoff:
  default_strict_after: "$cutoff"
EOF
        export LOA_AUDIT_VERIFY_SIGS=1
    else
        cat > "$LOA_TRUST_STORE_FILE" <<EOF
schema_version: "1.0"
root_signature:
  algorithm: ed25519
  signer_pubkey: ""
  signed_at: ""
  signature: ""
keys: []
revocations: []
trust_cutoff:
  default_strict_after: "2099-01-01T00:00:00Z"
EOF
        unset LOA_AUDIT_VERIFY_SIGS
    fi

    export LOA_AUDIT_KEY_DIR="$KEY_DIR"
    export LOA_AUDIT_SIGNING_KEY_ID="$key_id"
    export LOA_TRUST_STORE_FILE
    export TEST_DIR KEY_DIR
}

# -----------------------------------------------------------------------------
# signing_fixtures_teardown — clean up TEST_DIR + unset env. Idempotent.
# -----------------------------------------------------------------------------
signing_fixtures_teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_AUDIT_KEY_DIR LOA_AUDIT_SIGNING_KEY_ID LOA_TRUST_STORE_FILE \
          LOA_AUDIT_VERIFY_SIGS TEST_DIR KEY_DIR \
          _SIGN_FIX_KEY_ID _SIGN_FIX_PUBKEY_PEM
}

# -----------------------------------------------------------------------------
# signing_fixtures_register_extra_key <key_id>
#
# Generate a SECOND ephemeral key and register it in the trust-store. Used by
# tests that need multiple writers (e.g., revocation, multi-writer chains).
# Returns the new pubkey PEM on stdout.
# -----------------------------------------------------------------------------
signing_fixtures_register_extra_key() {
    local extra_id="$1"
    [[ -n "$extra_id" ]] || { echo "signing_fixtures_register_extra_key: requires <key_id>" >&2; return 1; }
    [[ -d "${KEY_DIR:-}" ]] || { echo "signing_fixtures_register_extra_key: signing_fixtures_setup must run first" >&2; return 1; }
    python3 - "$KEY_DIR" "$extra_id" <<'PY'
import sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization
key_dir = Path(sys.argv[1]); key_id = sys.argv[2]
priv = ed25519.Ed25519PrivateKey.generate()
(key_dir / f"{key_id}.priv").write_bytes(priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
))
(key_dir / f"{key_id}.priv").chmod(0o600)
(key_dir / f"{key_id}.pub").write_bytes(priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
))
PY
    local pem
    pem="$(cat "${KEY_DIR}/${extra_id}.pub")"
    # Append to trust-store keys[].
    if [[ -f "${LOA_TRUST_STORE_FILE:-}" ]]; then
        local pem_indented
        pem_indented="$(printf '%s\n' "$pem" | sed 's/^/      /')"
        # Use yq if available for safe in-place edit; fall back to Python.
        if command -v yq >/dev/null 2>&1; then
            yq -i '.keys += [{"writer_id": strenv(EXTRA_ID), "pubkey_pem": strenv(EXTRA_PEM)}]' \
                EXTRA_ID="$extra_id" EXTRA_PEM="$pem" "$LOA_TRUST_STORE_FILE" 2>/dev/null || true
        else
            python3 - "$LOA_TRUST_STORE_FILE" "$extra_id" "$pem" <<'PY'
import sys, yaml
path, kid, pem = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f: doc = yaml.safe_load(f)
doc.setdefault("keys", []).append({"writer_id": kid, "pubkey_pem": pem})
with open(path, "w") as f: yaml.safe_dump(doc, f, default_style="|")
PY
        fi
    fi
    printf '%s' "$pem"
}
