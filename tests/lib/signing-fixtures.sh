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
# Re-call safety: calling `signing_fixtures_setup` AFTER `_teardown` is safe
# (cleans up first via mktemp re-creation). Back-to-back setup without
# teardown will orphan the prior TEST_DIR — call teardown between setups if
# you need pristine state.
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
        # Fallback: walk up from cwd looking for the sentinel file (the very
        # script audit-envelope.sh that the helpers are about). Avoids the
        # pwd-resolves-wrong-dir failure mode iter-1 review flagged.
        local d
        d="$(pwd)"
        while [[ "$d" != "/" ]]; do
            if [[ -f "${d}/.claude/scripts/audit-envelope.sh" ]]; then
                echo "$d"
                return 0
            fi
            d="$(dirname "$d")"
        done
        echo "_sign_fix_repo_root: cannot locate repo root from $(pwd) (no .claude/scripts/audit-envelope.sh in any ancestor)" >&2
        return 1
    fi
}

# -----------------------------------------------------------------------------
# signing_fixtures_setup [--strict|--bootstrap] [--key-id <id>] [--cutoff <iso>]
# -----------------------------------------------------------------------------
signing_fixtures_setup() {
    local mode="strict"
    local mode_explicit=0
    local key_id="test-writer"
    local cutoff="2020-01-01T00:00:00Z"
    while (( "$#" )); do
        case "$1" in
            --strict)
                if (( mode_explicit == 1 )) && [[ "$mode" != "strict" ]]; then
                    echo "signing_fixtures_setup: --strict and --bootstrap are mutually exclusive" >&2
                    return 1
                fi
                mode="strict"; mode_explicit=1; shift ;;
            --bootstrap)
                if (( mode_explicit == 1 )) && [[ "$mode" != "bootstrap" ]]; then
                    echo "signing_fixtures_setup: --strict and --bootstrap are mutually exclusive" >&2
                    return 1
                fi
                mode="bootstrap"; mode_explicit=1; shift ;;
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
    # Use rm -rf for atomic cleanup — find -delete left behind any non-file
    # entries (symlinks, sockets) and forced the smoke test to weaken its
    # assertion (review iter-1 H1-teardown-find-vs-rm). For an mktemp dir we
    # control entirely, rm -rf is the idiomatic choice.
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf -- "$TEST_DIR"
    fi
    unset LOA_AUDIT_KEY_DIR LOA_AUDIT_SIGNING_KEY_ID LOA_TRUST_STORE_FILE \
          LOA_AUDIT_VERIFY_SIGS TEST_DIR KEY_DIR \
          _SIGN_FIX_KEY_ID _SIGN_FIX_PUBKEY_PEM
}

# -----------------------------------------------------------------------------
# signing_fixtures_register_extra_key <key_id> [--update-trust-store]
#
# Generate a SECOND ephemeral key and write its priv/pub PEM into KEY_DIR.
# By default does NOT touch the trust-store — tests that just need to switch
# `LOA_AUDIT_SIGNING_KEY_ID` between writers rely on the KEY_DIR fallback
# (the documented path in audit-envelope.sh:311) for pubkey resolution.
#
# Pass `--update-trust-store` to ALSO append `{writer_id, pubkey_pem}` to the
# trust-store's `keys[]`. WARNING: doing so trips the trust-store out of
# BOOTSTRAP-PENDING state (empty keys + empty revocations + empty root_sig
# is the BOOTSTRAP marker — adding a key flips it to NEEDS_VERIFY, which
# fails without a properly-signed `root_signature`). Tests using this flag
# are responsible for restoring trust-store validity (e.g., re-bootstrap
# with a maintainer-root-pubkey fixture, out of scope for this lib).
#
# Sprint H1 review remediation (HIGH-2): prior version silently appended to
# `keys[]` via a malformed yq invocation that always failed. The smoke test
# passed because the audit-envelope KEY_DIR fallback resolved the pubkey
# regardless of trust-store state. Function signature now matches actual
# behavior; trust-store update is opt-in and dangerous.
#
# Returns the new pubkey PEM on stdout.
# -----------------------------------------------------------------------------
signing_fixtures_register_extra_key() {
    local extra_id=""
    local update_trust_store=0
    while (( "$#" )); do
        case "$1" in
            --update-trust-store) update_trust_store=1; shift ;;
            --*) echo "signing_fixtures_register_extra_key: unknown flag $1" >&2; return 1 ;;
            *)
                if [[ -z "$extra_id" ]]; then extra_id="$1"
                else echo "signing_fixtures_register_extra_key: too many positional args" >&2; return 1
                fi
                shift ;;
        esac
    done
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
    if (( update_trust_store == 1 )) && [[ -f "${LOA_TRUST_STORE_FILE:-}" ]]; then
        # Caller acknowledged the BOOTSTRAP-PENDING transition risk via the
        # explicit flag. Use python+PyYAML adapter (the previous yq-via-env
        # form was malformed and silently failed — HIGH-2 finding).
        # Iter-2 review MEDIUM: explicit PyYAML availability check so the
        # missing-dep error is clear rather than a generic "failed to update".
        if ! python3 -c "import yaml" 2>/dev/null; then
            echo "signing_fixtures_register_extra_key --update-trust-store: PyYAML not installed (pip install pyyaml)" >&2
            return 1
        fi
        if ! python3 - "$LOA_TRUST_STORE_FILE" "$extra_id" "$pem" <<'PY'
import sys, yaml
path, kid, pem = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f: doc = yaml.safe_load(f) or {}
doc.setdefault("keys", []).append({"writer_id": kid, "pubkey_pem": pem})
with open(path, "w") as f: yaml.safe_dump(doc, f, default_flow_style=False)
PY
        then
            echo "signing_fixtures_register_extra_key: failed to update trust-store $LOA_TRUST_STORE_FILE" >&2
            return 1
        fi
        # Invalidate the audit-envelope trust-store status cache so the
        # next audit_emit re-checks. Prevents stale BOOTSTRAP-PENDING cache
        # from masking a now-INVALID trust-store.
        _LOA_AUDIT_TS_CACHE_PATH=""
        _LOA_AUDIT_TS_CACHE_KEY=""
        _LOA_AUDIT_TS_CACHE_STATUS=""
    fi
    printf '%s' "$pem"
}

# -----------------------------------------------------------------------------
# signing_fixtures_tamper_with_chain_repair <log> <line_n> <jq_filter>
#
# Rigorous payload-tampering helper for signed-mode tests (Sprint H1 review
# HIGH-1). The naive pattern `jq -c '.payload.x = "tampered"'` followed by
# audit_verify_chain catches the tamper via prev_hash chain validation alone
# — the test would pass even against a buggy signature verifier that always
# returns 0. To rigorously test SIGNATURE verification, we must repair the
# chain after tampering: recompute prev_hash of subsequent lines so the
# chain-hash check slides by, leaving signature mismatch as the ONLY failure
# mode. This makes the test signed-mode-specific.
#
# Args:
#   $1 — input log path (untouched)
#   $2 — 1-indexed line number to tamper
#   $3 — jq filter to apply to that line (e.g., '.payload.usd_used = 999')
#   $4 — output log path (where to write the chain-repaired tampered log)
#
# After this helper:
#   - audit_verify_chain $4 with LOA_AUDIT_VERIFY_SIGS=0 → SUCCESS
#     (chain hashes match because prev_hashes were repaired)
#   - audit_verify_chain $4 with LOA_AUDIT_VERIFY_SIGS=1 → FAIL
#     (signature on line $2 is invalid because payload changed but
#      signature was computed over the pre-tamper payload)
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# signing_fixtures_inject_chain_valid_envelope <log> <primitive_id> <event_type> <payload_json>
#
# Sprint H2 closure of #708 F-006 (cycle-098 audit fixture realism finding):
# forensic-failure tests in cost-budget-enforcer-state-machine.bats were
# injecting envelopes with `prev_hash="GENESIS"`, breaking chain continuity.
# The PRODUCTION threat is a chain-VALID log with anomalous payload values
# (e.g., counter goes backwards, drift exceeds threshold) — those slip past
# `audit_verify_chain` and require detection logic to catch them. Tests that
# inject chain-broken fixtures don't exercise the detection path.
#
# This helper computes the correct prev_hash from the existing tail (or
# "GENESIS" when the log is empty) and writes the envelope through the
# canonical Sprint 1A schema, with optional Sprint 1B signing if KEY_ID is
# set. The result is a chain-valid log entry that detection logic must
# notice based on payload anomalies, not chain breaks.
#
# Args:
#   $1 log path
#   $2 primitive_id (L1|L2|L3|L4|L5|L6|L7)
#   $3 event_type (e.g., "budget.record_call")
#   $4 payload JSON (single-line, schema-valid)
#
# Returns 0 on success.
# -----------------------------------------------------------------------------
signing_fixtures_inject_chain_valid_envelope() {
    local log_path="$1"
    local primitive_id="$2"
    local event_type="$3"
    local payload_json="$4"

    [[ -n "$log_path" && -n "$primitive_id" && -n "$event_type" && -n "$payload_json" ]] || {
        echo "inject_chain_valid_envelope: requires <log> <primitive_id> <event_type> <payload_json>" >&2
        return 1
    }

    if ! declare -f audit_emit >/dev/null 2>&1; then
        local repo_root
        repo_root="$(_sign_fix_repo_root)"
        # shellcheck source=/dev/null
        source "${repo_root}/.claude/scripts/audit-envelope.sh"
    fi

    # Ensure the log directory exists (audit_emit creates the file).
    local log_dir
    log_dir="$(dirname "$log_path")"
    mkdir -p "$log_dir"

    # audit_emit handles prev_hash computation + canonical envelope + signing.
    audit_emit "$primitive_id" "$event_type" "$payload_json" "$log_path"
}

signing_fixtures_tamper_with_chain_repair() {
    local input_log="$1"
    local line_n="$2"
    local jq_filter="$3"
    local output_log="$4"
    [[ -f "$input_log" ]] || { echo "tamper_with_chain_repair: input log $input_log missing" >&2; return 1; }
    [[ -n "$line_n" && "$line_n" =~ ^[0-9]+$ ]] || { echo "tamper_with_chain_repair: line_n must be a positive integer" >&2; return 1; }
    [[ -n "$jq_filter" ]] || { echo "tamper_with_chain_repair: requires <jq_filter>" >&2; return 1; }
    [[ -n "$output_log" ]] || { echo "tamper_with_chain_repair: requires <output_log>" >&2; return 1; }

    # Sprint H2 closure of H1 iter-2 LOW (H1-double-source-audit-envelope):
    # the prior defensive `source "${repo_root}/.claude/scripts/audit-envelope.sh"`
    # block here was dead code — _audit_chain_input is never called from this
    # function (the Python heredoc reimplements chain-input via subprocess).
    # Removed.

    local repo_root
    repo_root="$(_sign_fix_repo_root)"
    local jcs_helper="${repo_root}/.claude/scripts/lib/jcs-helper.py"
    [[ -f "$jcs_helper" ]] || { echo "tamper_with_chain_repair: jcs-helper.py not found at $jcs_helper" >&2; return 1; }

    python3 - "$input_log" "$line_n" "$jq_filter" "$output_log" "$jcs_helper" <<'PY'
import sys, hashlib, subprocess

input_log, line_n_str, jq_filter, output_log, jcs_helper = sys.argv[1:6]
line_n = int(line_n_str)

with open(input_log) as f:
    lines = [ln.rstrip("\n") for ln in f if ln.rstrip("\n")]

if line_n < 1 or line_n > len(lines):
    print(f"tamper_with_chain_repair: line {line_n} out of range (1..{len(lines)})", file=sys.stderr)
    sys.exit(1)

tamper_idx = line_n - 1
tampered = subprocess.run(
    ["jq", "-c", jq_filter],
    input=lines[tamper_idx], capture_output=True, text=True, check=True,
).stdout.strip()
lines[tamper_idx] = tampered

# chain-input bytes = JCS-canonical(envelope minus signature + signing_key_id).
# Hash → sha256 hex. Matches audit-envelope.sh:_audit_chain_input + _audit_sha256.
def chain_input_sha(env_json: str) -> str:
    stripped = subprocess.run(
        ["jq", "-c", "del(.signature, .signing_key_id)"],
        input=env_json, capture_output=True, text=True, check=True,
    ).stdout.strip()
    canonical = subprocess.run(
        ["python3", jcs_helper],
        input=stripped, capture_output=True, text=True, check=True,
    ).stdout
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

# Recompute prev_hash for line_n+1 onwards so the chain stays coherent.
for i in range(tamper_idx + 1, len(lines)):
    prev_idx = i - 1
    new_prev_hash = chain_input_sha(lines[prev_idx])
    repaired = subprocess.run(
        ["jq", "-c", f'.prev_hash = "{new_prev_hash}"'],
        input=lines[i], capture_output=True, text=True, check=True,
    ).stdout.strip()
    lines[i] = repaired

with open(output_log, "w") as f:
    for ln in lines:
        f.write(ln + "\n")
PY
}
