#!/usr/bin/env bash
# =============================================================================
# audit-envelope.sh — canonical write/read/verify path for L1-L7 audit logs.
#
# cycle-098 Sprint 1A foundation, extended in Sprint 1B with Ed25519 signing.
# All 7 primitives' JSONL audit logs use the same envelope shape from
# `.claude/data/trajectory-schemas/agent-network-envelope.schema.json`.
#
# Sprint 1A:
#   - audit_emit            : append a validated, hash-chained envelope
#   - audit_verify_chain    : walk a log; verify prev_hash continuity
#   - audit_seal_chain      : write final [<PRIMITIVE>-DISABLED] marker
#
# Sprint 1B (this revision):
#   - Ed25519 signing wired into audit_emit (when LOA_AUDIT_SIGNING_KEY_ID set)
#   - Ed25519 signature verification in audit_verify_chain
#   - audit_emit_signed: explicit signing entrypoint with --password-fd /
#     --password-file (SKP-002)
#   - audit_trust_store_verify: trust-store root-of-trust verification
#     against pinned root pubkey at .claude/data/maintainer-root-pubkey.txt
#   - LOA_AUDIT_KEY_PASSWORD env var DEPRECATED (warn on use)
#
# Sprint 1C: sanitize_for_session_start integration (untrusted-content fields).
# Sprint 1D: L1 panel-decisions integration.
#
# Conventions:
#   - Canonical-JSON via lib/jcs.sh (RFC 8785). NEVER substitute jq -S -c.
#   - Schema validation at write-time via ajv (Node) or jsonschema (Python fallback).
#   - JSONL: one envelope per line, no whitespace, terminated with \n.
#   - Private keys are NEVER passed via argv. Use --password-fd / --password-file.
# =============================================================================

set -euo pipefail

if [[ "${_LOA_AUDIT_ENVELOPE_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_AUDIT_ENVELOPE_SOURCED=1

_LOA_AUDIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LOA_AUDIT_REPO_ROOT="$(cd "${_LOA_AUDIT_DIR}/.." && pwd)"
_LOA_AUDIT_SCHEMA="${_LOA_AUDIT_REPO_ROOT}/data/trajectory-schemas/agent-network-envelope.schema.json"
_LOA_AUDIT_JCS_LIB="${_LOA_AUDIT_REPO_ROOT}/../lib/jcs.sh"
_LOA_AUDIT_SIGNING_HELPER="${_LOA_AUDIT_DIR}/lib/audit-signing-helper.py"

# Source JCS canonicalizer.
# shellcheck source=../../lib/jcs.sh
source "${_LOA_AUDIT_JCS_LIB}"

# Schema version this writer emits. Bump major on breaking schema change.
# Sprint 1B: bumped to 1.1.0 to mark signature/signing_key_id presence.
LOA_AUDIT_SCHEMA_VERSION="${LOA_AUDIT_SCHEMA_VERSION:-1.1.0}"

# Default key directory: ~/.config/loa/audit-keys/ — overridable via
# LOA_AUDIT_KEY_DIR. The trust-store is at grimoires/loa/trust-store.yaml.
_LOA_AUDIT_DEFAULT_KEY_DIR="${HOME:-/tmp}/.config/loa/audit-keys"
_LOA_AUDIT_PINNED_PUBKEY="${LOA_PINNED_ROOT_PUBKEY_PATH:-${_LOA_AUDIT_REPO_ROOT}/data/maintainer-root-pubkey.txt}"
_LOA_AUDIT_TRUST_STORE_DEFAULT="${_LOA_AUDIT_REPO_ROOT}/../grimoires/loa/trust-store.yaml"

# -----------------------------------------------------------------------------
# _audit_log() — internal logging helper. Goes to stderr to avoid corrupting stdout.
# -----------------------------------------------------------------------------
_audit_log() {
    echo "[audit-envelope] $*" >&2
}

# -----------------------------------------------------------------------------
# _audit_require_flock — F3 (CC-3 review remediation): ensure `flock` is on
# PATH. On macOS, flock lives in homebrew util-linux at a keg-only path that
# is NOT exported by default. Falls back to the same path-resolution pattern
# used by .claude/scripts/lib/event-bus.sh (#229).
# Returns 0 if flock is now usable; non-zero if not.
# -----------------------------------------------------------------------------
_audit_require_flock() {
    if command -v flock >/dev/null 2>&1; then
        return 0
    fi
    if [[ "$(uname -s)" == "Darwin" ]]; then
        local keg_paths=(
            "/opt/homebrew/opt/util-linux/bin"
            "/usr/local/opt/util-linux/bin"
        )
        local keg_path
        for keg_path in "${keg_paths[@]}"; do
            if [[ -x "${keg_path}/flock" ]]; then
                export PATH="${keg_path}:${PATH}"
                return 0
            fi
        done
        _audit_log "ERROR: audit-envelope requires flock for atomic chain writes (CC-3)."
        _audit_log "  Install on macOS: brew install util-linux"
        return 1
    fi
    _audit_log "ERROR: audit-envelope requires flock for atomic chain writes (CC-3)."
    _audit_log "  Install: apt-get install util-linux"
    return 1
}

# -----------------------------------------------------------------------------
# _audit_now_iso8601() — produce microsecond-precision UTC ISO-8601 timestamp.
# Format: 2026-05-02T14:30:00.123456Z
# Cross-platform: GNU date supports %N (nanoseconds); macOS does not.
# -----------------------------------------------------------------------------
_audit_now_iso8601() {
    # Test override (Sprint 2 remediation): tests that set LOA_AUDIT_TEST_NOW
    # to a fixed ISO-8601 timestamp get a deterministic clock for envelope
    # ts_utc. Production callers don't set this; behavior identical to before.
    if [[ -n "${LOA_AUDIT_TEST_NOW:-}" ]]; then
        echo "$LOA_AUDIT_TEST_NOW"
        return 0
    fi
    if date +%6N 2>/dev/null | grep -q '^[0-9]\{6\}$'; then
        date -u +"%Y-%m-%dT%H:%M:%S.%6NZ"
    else
        # macOS / BSD date — fall back to Python for microsecond precision.
        python3 -c '
from datetime import datetime, timezone
print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"))
'
    fi
}

# -----------------------------------------------------------------------------
# _audit_sha256() — SHA-256 hex digest of stdin bytes.
# Tries `sha256sum` (Linux) first, then `shasum -a 256` (macOS), then python3.
# -----------------------------------------------------------------------------
_audit_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        python3 -c '
import hashlib, sys
print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())
'
    fi
}

# -----------------------------------------------------------------------------
# _audit_chain_input <envelope_json>
#
# Compute the canonical bytes used as input to prev_hash + signature. Excludes
# `signature` and `signing_key_id` per SDD §1.4.1 spec. Uses JCS canonicalization.
# -----------------------------------------------------------------------------
_audit_chain_input() {
    local envelope_json="$1"
    # Strip signature + signing_key_id, then canonicalize.
    local stripped
    stripped="$(printf '%s' "$envelope_json" | jq -c 'del(.signature, .signing_key_id)')"
    jcs_canonicalize "$stripped"
}

# -----------------------------------------------------------------------------
# _audit_compute_prev_hash <log_path>
#
# Read the last line of <log_path>, compute SHA-256 of its canonical chain-input.
# Emit "GENESIS" if the file does not exist or is empty.
# -----------------------------------------------------------------------------
_audit_compute_prev_hash() {
    local log_path="$1"
    if [[ ! -f "$log_path" ]] || [[ ! -s "$log_path" ]]; then
        echo "GENESIS"
        return 0
    fi
    local last_line
    last_line="$(tail -n 1 "$log_path")"
    if [[ -z "$last_line" ]]; then
        echo "GENESIS"
        return 0
    fi
    # Skip seal markers (lines starting with `[`) — they're not envelopes.
    if [[ "$last_line" == \[* ]]; then
        # Find last non-marker line.
        last_line="$(grep -v '^\[' "$log_path" | tail -n 1 || true)"
        if [[ -z "$last_line" ]]; then
            echo "GENESIS"
            return 0
        fi
    fi
    _audit_chain_input "$last_line" | _audit_sha256
}

# -----------------------------------------------------------------------------
# _audit_validate_envelope <envelope_json>
#
# Validate against the envelope schema. Tries ajv first; falls back to Python
# jsonschema (R15: behavior identical between adapters).
# Returns 0 valid; 1 invalid; 2 no validator available.
# -----------------------------------------------------------------------------
_audit_validate_envelope() {
    local envelope_json="$1"
    if [[ ! -f "${_LOA_AUDIT_SCHEMA}" ]]; then
        _audit_log "schema file missing at ${_LOA_AUDIT_SCHEMA}"
        return 2
    fi

    # Prefer ajv if available.
    if command -v ajv >/dev/null 2>&1; then
        local tmp_data
        tmp_data="$(mktemp)"
        chmod 600 "$tmp_data"
        # shellcheck disable=SC2064
        trap "rm -f '$tmp_data'" RETURN
        printf '%s' "$envelope_json" > "$tmp_data"
        if ajv validate -s "${_LOA_AUDIT_SCHEMA}" -d "$tmp_data" --spec=draft2020 >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi

    # Python jsonschema fallback.
    LOA_ENVELOPE_JSON="$envelope_json" \
    LOA_SCHEMA_PATH="${_LOA_AUDIT_SCHEMA}" \
    python3 - <<'PY'
import json, os, sys
try:
    import jsonschema
except ImportError:
    print("audit-envelope: neither ajv nor jsonschema available", file=sys.stderr)
    sys.exit(2)

envelope = json.loads(os.environ["LOA_ENVELOPE_JSON"])
with open(os.environ["LOA_SCHEMA_PATH"]) as f:
    schema = json.load(f)
try:
    jsonschema.validate(envelope, schema)
except jsonschema.ValidationError as e:
    print(f"audit-envelope: schema validation failed: {e.message}", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
}

# -----------------------------------------------------------------------------
# _audit_resolve_key_dir — return the active key directory (LOA_AUDIT_KEY_DIR
# if set, otherwise ~/.config/loa/audit-keys).
# -----------------------------------------------------------------------------
_audit_resolve_key_dir() {
    echo "${LOA_AUDIT_KEY_DIR:-${_LOA_AUDIT_DEFAULT_KEY_DIR}}"
}

# -----------------------------------------------------------------------------
# _audit_sign_chain_input <signing_key_id> <chain_input_bytes> [pw-flags...]
#
# Read canonical-JSON bytes from stdin, return base64 Ed25519 signature on
# stdout. Honors --password-fd N / --password-file PATH passed via additional
# args (forwarded verbatim to the signing helper).
#
# IMPORTANT: do NOT pass the password as an argument. xtrace-disable around
# any block that touches the helper.
# -----------------------------------------------------------------------------
_audit_sign_stdin() {
    local key_id="$1"; shift
    local key_dir
    key_dir="$(_audit_resolve_key_dir)"

    # BB-001: temporarily disable xtrace to avoid leaking password-file paths
    # or fd numbers in trace output.
    local _xtrace_was_on=0
    case "$-" in *x*) _xtrace_was_on=1; set +x ;; esac

    python3 "${_LOA_AUDIT_SIGNING_HELPER}" sign \
        --key-id "$key_id" --key-dir "$key_dir" "$@"
    local rc=$?

    [[ "$_xtrace_was_on" == "1" ]] && set -x
    return "$rc"
}

# -----------------------------------------------------------------------------
# _audit_verify_signature <pubkey-pem> <canonical_bytes> <sig_b64>
# Returns 0 on valid, non-zero on invalid. Writes nothing to stdout.
# -----------------------------------------------------------------------------
_audit_verify_signature_inline() {
    local pubkey_pem="$1"
    local canonical_bytes="$2"
    local sig_b64="$3"

    {
        printf '%s' "$canonical_bytes"
        printf '\n'
        printf '%s' "$sig_b64"
    } | python3 "${_LOA_AUDIT_SIGNING_HELPER}" verify-inline \
            --pubkey-pem "$pubkey_pem" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# _audit_pubkey_for_key_id <key_id>
# Resolve the public-key PEM for <key_id>:
#   1. Trust-store at grimoires/loa/trust-store.yaml — preferred path
#   2. Local fallback: <key-dir>/<key_id>.pub (used in tests + CI)
# Returns the PEM on stdout, non-zero exit if not resolvable.
# -----------------------------------------------------------------------------
_audit_pubkey_for_key_id() {
    local key_id="$1"

    # Prefer trust-store entry when available.
    local trust_store="${LOA_TRUST_STORE_FILE:-${_LOA_AUDIT_TRUST_STORE_DEFAULT}}"
    if [[ -f "$trust_store" ]] && command -v yq >/dev/null 2>&1; then
        local pem
        pem="$(yq -r --arg id "$key_id" \
            '.keys[]? | select(.writer_id == $id) | .pubkey_pem // ""' \
            "$trust_store" 2>/dev/null || true)"
        if [[ -n "$pem" && "$pem" != "null" ]]; then
            printf '%s\n' "$pem"
            return 0
        fi
    fi

    # Fallback: local <key-dir>/<key_id>.pub (test path).
    local key_dir
    key_dir="$(_audit_resolve_key_dir)"
    local pub_path="${key_dir}/${key_id}.pub"
    if [[ -f "$pub_path" ]]; then
        cat "$pub_path"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Issue #690 auto-verify cache: per-process, (mtime, size, sha256)-keyed.
# Bridgebuilder F4 (Sprint 1.5): mtime-alone is racy on second-granularity
# filesystems (ext4 without nsec, FAT, some NFS configs) — Linus's "racy git"
# 2014 problem. Same-second tampering bypasses mtime invalidation. Adding
# size + content-hash to the key closes the TOCTOU window.
# -----------------------------------------------------------------------------
_LOA_AUDIT_TS_CACHE_PATH=""
_LOA_AUDIT_TS_CACHE_KEY=""
_LOA_AUDIT_TS_CACHE_STATUS=""

# -----------------------------------------------------------------------------
# _audit_file_mtime <path> — cross-platform mtime (seconds since epoch).
# -----------------------------------------------------------------------------
_audit_file_mtime() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    if stat -c %Y "$f" 2>/dev/null; then return 0; fi
    if stat -f %m "$f" 2>/dev/null; then return 0; fi
    python3 -c "import os, sys; print(int(os.stat(sys.argv[1]).st_mtime))" "$f" 2>/dev/null
}

# -----------------------------------------------------------------------------
# _audit_file_size <path> — cross-platform size in bytes.
# -----------------------------------------------------------------------------
_audit_file_size() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    if stat -c %s "$f" 2>/dev/null; then return 0; fi
    if stat -f %z "$f" 2>/dev/null; then return 0; fi
    wc -c < "$f" 2>/dev/null | awk '{print $1}'
}

# -----------------------------------------------------------------------------
# _audit_file_sha256 <path> — content-hash for cache key (bridgebuilder F4).
# -----------------------------------------------------------------------------
_audit_file_sha256_of() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    _audit_sha256 < "$f"
}

# -----------------------------------------------------------------------------
# _audit_ts_cache_key <path> — emit "mtime:size:sha256" for trust-store path.
# Used as the auto-verify cache key (F4 hardening).
# -----------------------------------------------------------------------------
_audit_ts_cache_key() {
    local f="$1"
    local mtime size sha
    mtime="$(_audit_file_mtime "$f" 2>/dev/null || echo "0")"
    size="$(_audit_file_size "$f" 2>/dev/null || echo "0")"
    sha="$(_audit_file_sha256_of "$f" 2>/dev/null || echo "")"
    printf '%s:%s:%s' "$mtime" "$size" "$sha"
}

# -----------------------------------------------------------------------------
# _audit_trust_store_status — auto-verify the active trust-store, returning
# one of: BOOTSTRAP-PENDING | VERIFIED | INVALID | MISSING (printed on stdout).
#
# Issue #690 (Sprint 1.5): runtime auto-verify hook called from audit_emit +
# audit_verify_chain. Cached per-process, mtime-invalidated.
#
# BOOTSTRAP-PENDING is the graceful-fallback state for empty/un-signed trust
# stores: the operator has not yet bootstrapped a signed trust-store, so
# permitting reads/writes lets cycle-098 install incrementally without
# requiring the maintainer-offline-root-key ceremony at install time.
# Once any keys[] or revocations[] entries land, the trust-store MUST be
# signed by the pinned root key — otherwise the trust-store is INVALID.
# -----------------------------------------------------------------------------
_audit_trust_store_status() {
    local trust_store="${LOA_TRUST_STORE_FILE:-${_LOA_AUDIT_TRUST_STORE_DEFAULT}}"

    # No trust-store file → BOOTSTRAP-PENDING (cycle-098 install-time default).
    if [[ ! -f "$trust_store" ]]; then
        echo "BOOTSTRAP-PENDING"
        return 0
    fi

    local cache_key
    cache_key="$(_audit_ts_cache_key "$trust_store")"

    # Cache hit? Key is (mtime, size, sha256) — F4 bridgebuilder hardening.
    if [[ "$_LOA_AUDIT_TS_CACHE_PATH" == "$trust_store" ]] && \
       [[ -n "$_LOA_AUDIT_TS_CACHE_KEY" ]] && \
       [[ "$_LOA_AUDIT_TS_CACHE_KEY" == "$cache_key" ]] && \
       [[ -n "$_LOA_AUDIT_TS_CACHE_STATUS" ]]; then
        echo "$_LOA_AUDIT_TS_CACHE_STATUS"
        return 0
    fi

    # Detect BOOTSTRAP-PENDING: empty signature + empty keys + empty revocations.
    local detect
    detect="$(python3 - "$trust_store" <<'PY' 2>/dev/null || true
import sys
try:
    import yaml
except ImportError:
    print("NEEDS_VERIFY")
    sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print("BOOTSTRAP-PENDING")
    sys.exit(0)
sig = ((doc.get("root_signature") or {}).get("signature") or "").strip()
keys = doc.get("keys") or []
revs = doc.get("revocations") or []
if not sig and not keys and not revs:
    print("BOOTSTRAP-PENDING")
else:
    print("NEEDS_VERIFY")
PY
)"

    local status
    if [[ "$detect" == "BOOTSTRAP-PENDING" ]]; then
        status="BOOTSTRAP-PENDING"
    else
        if audit_trust_store_verify "$trust_store" >/dev/null 2>&1; then
            status="VERIFIED"
        else
            status="INVALID"
        fi
    fi

    _LOA_AUDIT_TS_CACHE_PATH="$trust_store"
    _LOA_AUDIT_TS_CACHE_KEY="$cache_key"
    _LOA_AUDIT_TS_CACHE_STATUS="$status"
    echo "$status"
}

# -----------------------------------------------------------------------------
# _audit_check_trust_store — gate function called at top of audit_emit and
# audit_verify_chain. Returns 0 to permit, non-zero to block.
# On INVALID: emits [TRUST-STORE-INVALID] BLOCKER on stderr.
# -----------------------------------------------------------------------------
_audit_check_trust_store() {
    local status
    status="$(_audit_trust_store_status)"
    case "$status" in
        BOOTSTRAP-PENDING|VERIFIED)
            return 0
            ;;
        INVALID)
            _audit_log "[TRUST-STORE-INVALID] trust-store root_signature does NOT verify against pinned root pubkey; refusing all writes/reads (issue #690)"
            return 1
            ;;
        *)
            _audit_log "[TRUST-STORE-INVALID] unrecognized trust-store status: $status"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# audit_trust_store_verify <trust_store_path>
#
# Verify the trust-store's root_signature against the pinned root pubkey at
# .claude/data/maintainer-root-pubkey.txt (or LOA_PINNED_ROOT_PUBKEY_PATH).
#
# Multi-channel: on signer_pubkey != pinned_pubkey mismatch, emit
# `[ROOT-PUBKEY-DIVERGENCE]` BLOCKER.
#
# Returns 0 on valid, non-zero on any failure. Always emits diagnostic stderr.
# -----------------------------------------------------------------------------
audit_trust_store_verify() {
    local ts_path="${1:-${_LOA_AUDIT_TRUST_STORE_DEFAULT}}"
    local pinned="${LOA_PINNED_ROOT_PUBKEY_PATH:-${_LOA_AUDIT_PINNED_PUBKEY}}"

    if [[ ! -f "$pinned" ]]; then
        _audit_log "[ROOT-PUBKEY-MISSING] pinned root pubkey not found: $pinned"
        return 78
    fi
    if [[ ! -f "$ts_path" ]]; then
        _audit_log "trust-store not found: $ts_path"
        return 1
    fi

    python3 "${_LOA_AUDIT_SIGNING_HELPER}" trust-store-verify \
        --pinned-pubkey "$pinned" \
        --trust-store "$ts_path"
}

# -----------------------------------------------------------------------------
# audit_emit_signed <primitive_id> <event_type> <payload_json> <log_path> [--password-fd N|--password-file PATH]
#
# Explicit signing entrypoint. Same as audit_emit but with mandatory signing
# key + password-fd/file support (SKP-002).
#
# After signing completes, scrubs LOA_AUDIT_KEY_PASSWORD from the parent
# environment as defense-in-depth (operators should not be using the env var
# in the first place; the warning is emitted by the helper).
# -----------------------------------------------------------------------------
audit_emit_signed() {
    local primitive_id="$1"
    local event_type="$2"
    local payload_json="$3"
    local log_path="$4"
    shift 4

    # Forward any --password-fd / --password-file flags via env to audit_emit.
    LOA_AUDIT_FORWARD_PW_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --password-fd|--password-file)
                LOA_AUDIT_FORWARD_PW_ARGS+=("$1" "$2")
                shift 2
                ;;
            *)
                _audit_log "audit_emit_signed: unknown arg: $1"
                return 2
                ;;
        esac
    done

    # When called as audit_emit_signed, signing is REQUIRED.
    if [[ -z "${LOA_AUDIT_SIGNING_KEY_ID:-}" ]]; then
        _audit_log "audit_emit_signed: LOA_AUDIT_SIGNING_KEY_ID not set"
        return 2
    fi

    audit_emit "$primitive_id" "$event_type" "$payload_json" "$log_path"
    local rc=$?

    # Scrub deprecated env var post-call (defense-in-depth per SKP-002).
    unset LOA_AUDIT_KEY_PASSWORD 2>/dev/null || true
    unset LOA_AUDIT_FORWARD_PW_ARGS 2>/dev/null || true
    return "$rc"
}

# -----------------------------------------------------------------------------
# audit_emit <primitive_id> <event_type> <payload_json> <log_path>
#
# Build a validated envelope, append (atomically) to <log_path> as JSONL.
# Computes prev_hash from the existing log; assigns ts_utc; validates schema.
#
# Sprint 1B: when LOA_AUDIT_SIGNING_KEY_ID is set, signs the canonical
# chain-input bytes with Ed25519 and populates signature + signing_key_id.
# When unset, behaves as Sprint 1A (signature fields omitted; schema allows).
# -----------------------------------------------------------------------------
audit_emit() {
    local primitive_id="$1"
    local event_type="$2"
    local payload_json="$3"
    local log_path="$4"

    # Validate inputs.
    if [[ -z "$primitive_id" || -z "$event_type" || -z "$payload_json" || -z "$log_path" ]]; then
        _audit_log "audit_emit: missing required argument"
        return 2
    fi

    # Issue #690 (Sprint 1.5): auto-verify trust-store before any write.
    # BOOTSTRAP-PENDING + VERIFIED permit; INVALID blocks with [TRUST-STORE-INVALID].
    _audit_check_trust_store || return 1

    # Validate payload is JSON object.
    if ! printf '%s' "$payload_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
        _audit_log "audit_emit: payload must be a JSON object"
        return 2
    fi

    # Ensure parent dir exists.
    local log_dir
    log_dir="$(dirname "$log_path")"
    mkdir -p "$log_dir"

    # F3 (CC-3 review remediation): acquire flock on <log_path>.lock for the
    # entire compute-prev-hash → sign → validate → append sequence. Without
    # this, concurrent writers race between _audit_compute_prev_hash (read
    # tail) and >> (append), producing missing entries or chain corruption.
    # Lock is held by ALL audit_emit callers — panel_log_*, override CLI,
    # cost-budget writes, etc.
    _audit_require_flock || return 1

    local lock_file="${log_path}.lock"
    # Touch lock so flock has a stable file to lock on.
    : > "$lock_file" 2>/dev/null || touch "$lock_file"

    # Open fd 9 on the lock file, then flock fd 9.
    # Wait up to 10s; this should be ample for any single-line append.
    {
        flock -w 10 9 || {
            _audit_log "audit_emit: failed to acquire lock on $lock_file (timeout 10s)"
            return 1
        }

        local ts_utc prev_hash
        ts_utc="$(_audit_now_iso8601)"
        prev_hash="$(_audit_compute_prev_hash "$log_path")"

        # Build envelope (Sprint 1B: signature + signing_key_id added when configured).
        local envelope
        envelope="$(jq -nc \
            --arg sv "$LOA_AUDIT_SCHEMA_VERSION" \
            --arg pid "$primitive_id" \
            --arg et "$event_type" \
            --arg ts "$ts_utc" \
            --arg ph "$prev_hash" \
            --argjson payload "$payload_json" \
            '{
                schema_version: $sv,
                primitive_id: $pid,
                event_type: $et,
                ts_utc: $ts,
                prev_hash: $ph,
                payload: $payload,
                redaction_applied: null
            }')"

        # Sprint 1B: Sign the canonical chain-input when LOA_AUDIT_SIGNING_KEY_ID
        # is set. The chain-input is the JCS canonicalization of the envelope WITHOUT
        # signature/signing_key_id (matches _audit_chain_input).
        if [[ -n "${LOA_AUDIT_SIGNING_KEY_ID:-}" ]]; then
            local canonical sig_b64
            canonical="$(_audit_chain_input "$envelope")"
            # Forward password-fd/file args from caller (audit_emit_signed sets these).
            local pw_args=()
            if [[ -n "${LOA_AUDIT_FORWARD_PW_ARGS+set}" ]]; then
                pw_args=(${LOA_AUDIT_FORWARD_PW_ARGS[@]+"${LOA_AUDIT_FORWARD_PW_ARGS[@]}"})
            fi
            if ! sig_b64="$(printf '%s' "$canonical" | _audit_sign_stdin "$LOA_AUDIT_SIGNING_KEY_ID" ${pw_args[@]+"${pw_args[@]}"})"; then
                _audit_log "audit_emit: signing failed for key_id=$LOA_AUDIT_SIGNING_KEY_ID"
                return 1
            fi
            envelope="$(printf '%s' "$envelope" | jq -c \
                --arg kid "$LOA_AUDIT_SIGNING_KEY_ID" \
                --arg sig "$sig_b64" \
                '. + {signing_key_id: $kid, signature: $sig}')"
        fi

        # Validate against schema.
        if ! _audit_validate_envelope "$envelope"; then
            _audit_log "audit_emit: schema validation failed for primitive=$primitive_id event=$event_type"
            return 1
        fi

        # Append the envelope atomically (within the lock).
        printf '%s\n' "$envelope" >> "$log_path"
    } 9>"$lock_file"
}

# -----------------------------------------------------------------------------
# _audit_trust_cutoff — read trust_cutoff.default_strict_after from the active
# trust-store. Returns ISO-8601 string on stdout; empty on missing/unreadable.
# -----------------------------------------------------------------------------
_audit_trust_cutoff() {
    local trust_store="${LOA_TRUST_STORE_FILE:-${_LOA_AUDIT_TRUST_STORE_DEFAULT}}"
    [[ -f "$trust_store" ]] || return 0
    if command -v yq >/dev/null 2>&1; then
        local cutoff
        cutoff="$(yq -r '.trust_cutoff.default_strict_after // ""' "$trust_store" 2>/dev/null || true)"
        [[ "$cutoff" == "null" ]] && cutoff=""
        printf '%s' "$cutoff"
        return 0
    fi
    # Python fallback for environments without yq.
    python3 - "$trust_store" <<'PY' 2>/dev/null || true
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
cutoff = (doc.get("trust_cutoff") or {}).get("default_strict_after", "")
if cutoff is not None:
    print(cutoff, end="")
PY
}

# -----------------------------------------------------------------------------
# _audit_ts_ge_cutoff <ts_utc> <cutoff_iso8601>
# Returns 0 if ts_utc >= cutoff (post-cutoff), 1 otherwise.
# Empty cutoff => returns 1 (no cutoff configured = grandfather all).
# Lexicographic comparison works for ISO-8601 in UTC (Z-suffixed).
# -----------------------------------------------------------------------------
_audit_ts_ge_cutoff() {
    local ts="$1"
    local cutoff="$2"
    [[ -z "$cutoff" ]] && return 1
    [[ -z "$ts" ]] && return 1
    [[ "$ts" > "$cutoff" || "$ts" == "$cutoff" ]] && return 0
    return 1
}

# -----------------------------------------------------------------------------
# audit_verify_chain <log_path>
#
# Walk the JSONL log; verify each entry's prev_hash matches the SHA-256 of the
# canonicalized chain-input of the previous entry. First entry must have
# prev_hash == "GENESIS".
#
# Sprint 1B: when an entry has signature + signing_key_id, also verifies the
# Ed25519 signature against the pubkey resolved via _audit_pubkey_for_key_id.
# When LOA_AUDIT_VERIFY_SIGS=0 (or empty), signature verification is skipped
# (used for 1A-style chain-only verification on un-signed logs).
#
# F1 (review remediation): for entries with ts_utc >= trust_cutoff, BOTH
# signature AND signing_key_id are REQUIRED. Stripping either is a downgrade
# attack and produces [STRIP-ATTACK-DETECTED]. Pre-cutoff entries are
# grandfathered (sign-optional) per IMP-002.
#
# Output: prints "OK <N entries>" on success; "BROKEN <line N: reason>" on
# first mismatch and exits non-zero.
# -----------------------------------------------------------------------------
audit_verify_chain() {
    local log_path="$1"
    if [[ ! -f "$log_path" ]]; then
        _audit_log "audit_verify_chain: file not found: $log_path"
        return 2
    fi

    # Issue #690 (Sprint 1.5): auto-verify trust-store before chain walk.
    # An attacker who tampers trust-store.yaml (adds malicious writer pubkey,
    # signs entries with corresponding private key) is undetected without this.
    _audit_check_trust_store || return 1

    local lineno=0
    local expected_prev="GENESIS"
    local count=0
    # Default: verify signatures when present. Operators can opt out via
    # LOA_AUDIT_VERIFY_SIGS=0 (e.g., for migrating un-signed logs).
    local verify_sigs="${LOA_AUDIT_VERIFY_SIGS:-1}"
    # F1: trust-cutoff for strict signature requirement (post-cutoff only).
    local cutoff
    cutoff="$(_audit_trust_cutoff)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        # Skip seal markers + blank lines.
        if [[ -z "$line" ]] || [[ "$line" == \[* ]]; then
            continue
        fi
        # Parse prev_hash.
        local actual_prev
        if ! actual_prev="$(printf '%s' "$line" | jq -r '.prev_hash // empty' 2>/dev/null)"; then
            echo "BROKEN line $lineno: not valid JSON" >&2
            return 1
        fi
        if [[ -z "$actual_prev" ]]; then
            echo "BROKEN line $lineno: missing prev_hash" >&2
            return 1
        fi
        if [[ "$actual_prev" != "$expected_prev" ]]; then
            echo "BROKEN line $lineno: prev_hash mismatch (got $actual_prev, expected $expected_prev)" >&2
            return 1
        fi

        # Sprint 1B signature verification (only when signature field present
        # AND verification is enabled).
        if [[ "$verify_sigs" != "0" ]]; then
            local sig_b64 kid ts_utc
            sig_b64="$(printf '%s' "$line" | jq -r '.signature // ""' 2>/dev/null)"
            kid="$(printf '%s' "$line" | jq -r '.signing_key_id // ""' 2>/dev/null)"
            ts_utc="$(printf '%s' "$line" | jq -r '.ts_utc // ""' 2>/dev/null)"

            # F1: strict requirement post-trust-cutoff. Both signature AND
            # signing_key_id MUST be present. Missing either => downgrade attack.
            if _audit_ts_ge_cutoff "$ts_utc" "$cutoff"; then
                if [[ -z "$sig_b64" || -z "$kid" ]]; then
                    echo "BROKEN line $lineno: [STRIP-ATTACK-DETECTED] signature required post-cutoff (cutoff=$cutoff, ts=$ts_utc, sig=$([[ -n "$sig_b64" ]] && echo present || echo MISSING), kid=$([[ -n "$kid" ]] && echo present || echo MISSING))" >&2
                    return 1
                fi
            fi

            if [[ -n "$sig_b64" && -n "$kid" ]]; then
                local pubkey_pem canonical
                if ! pubkey_pem="$(_audit_pubkey_for_key_id "$kid" 2>/dev/null)"; then
                    echo "BROKEN line $lineno: cannot resolve public key for signing_key_id=$kid" >&2
                    return 1
                fi
                canonical="$(_audit_chain_input "$line")"
                if ! _audit_verify_signature_inline "$pubkey_pem" "$canonical" "$sig_b64"; then
                    echo "BROKEN line $lineno: signature verification failed for signing_key_id=$kid" >&2
                    return 1
                fi
            fi
        fi

        # Compute hash of THIS entry's chain-input for the next iteration.
        expected_prev="$(_audit_chain_input "$line" | _audit_sha256)"
        count=$((count + 1))
    done < "$log_path"

    echo "OK $count entries"
    return 0
}

# -----------------------------------------------------------------------------
# _audit_primitive_id_for_log <log_path>
# Heuristic: derive primitive_id from the log filename. Recovery uses this to
# locate the matching snapshot archive entry. Falls back to inspecting the
# first envelope's primitive_id when filename is uninformative.
# -----------------------------------------------------------------------------
_audit_primitive_id_for_log() {
    local log_path="$1"
    local base
    base="$(basename "$log_path")"
    case "$base" in
        panel-decisions*) echo "L1"; return 0 ;;
        cost-budget-events*) echo "L2"; return 0 ;;
        cycles*) echo "L3"; return 0 ;;
        trust-ledger*) echo "L4"; return 0 ;;
        *)
            # Inspect first envelope-like line.
            if [[ -f "$log_path" ]]; then
                local first
                first="$(grep -v '^\[' "$log_path" 2>/dev/null | head -n 1 || true)"
                if [[ -n "$first" ]]; then
                    local pid
                    pid="$(printf '%s' "$first" | jq -r '.primitive_id // empty' 2>/dev/null || echo "")"
                    if [[ -n "$pid" ]]; then
                        echo "$pid"
                        return 0
                    fi
                fi
            fi
            echo ""
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# _audit_log_is_tracked <log_path>
# Returns 0 if the log is currently tracked in git (has a non-empty git history).
# Returns 1 if untracked / no git repo / no history.
# -----------------------------------------------------------------------------
_audit_log_is_tracked() {
    local log_path="$1"
    # Are we inside a git repo?
    if ! git -C "$(dirname "$log_path")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 1
    fi
    # Does this file have any git history?
    local commits
    commits="$(git -C "$(dirname "$log_path")" log --oneline -- "$(basename "$log_path")" 2>/dev/null | wc -l | awk '{print $1}')"
    if [[ "${commits:-0}" -gt 0 ]]; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# _audit_chain_validates_lines <jsonl_text>
# Walks chain from a JSONL string (newline-separated envelopes), returns 0 if
# the chain is valid, non-zero on first break. Skips marker lines (`[...]`).
# -----------------------------------------------------------------------------
_audit_chain_validates_lines() {
    local text="$1"
    local expected_prev="GENESIS"
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == \[* ]] && continue
        local actual_prev
        actual_prev="$(printf '%s' "$line" | jq -r '.prev_hash // empty' 2>/dev/null || echo "")"
        if [[ -z "$actual_prev" ]] || [[ "$actual_prev" != "$expected_prev" ]]; then
            return 1
        fi
        expected_prev="$(_audit_chain_input "$line" | _audit_sha256)"
    done <<< "$text"
    return 0
}

# -----------------------------------------------------------------------------
# _audit_recover_from_git <log_path>
# For TRACKED logs (L4 trust-ledger, L6 INDEX): walk `git log --oneline` newest
# to oldest; for each commit, fetch the file content via `git show`; check
# whether the chain validates; first match wins. Rewrite the log to that
# state + append [CHAIN-GAP-RECOVERED-FROM-GIT] + [CHAIN-RECOVERED] markers.
# Returns 0 on success, non-zero otherwise.
# -----------------------------------------------------------------------------
_audit_recover_from_git() {
    local log_path="$1"
    local git_dir
    git_dir="$(dirname "$log_path")"

    if ! git -C "$git_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 1
    fi

    # Resolve the repo root + repo-relative path. The previous implementation
    # used basename(log_path) which failed for logs in subdirectories
    # (e.g., .run/trust-ledger.jsonl) because git pathspecs and `git show
    # <commit>:<path>` are repo-rooted, not log-dir-rooted. cycle-098 sprint-4
    # uncovered this when L4 began exercising audit_recover_chain via
    # trust_recover_chain.
    local repo_root abs_log rel_to_root
    repo_root="$(git -C "$git_dir" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -z "$repo_root" ]]; then
        return 1
    fi
    # Canonicalize the log path so realpath gives us a comparable string.
    if command -v realpath >/dev/null 2>&1; then
        abs_log="$(realpath "$log_path" 2>/dev/null || true)"
    else
        abs_log="$(cd "$git_dir" && pwd)/$(basename "$log_path")"
    fi
    if [[ -z "$abs_log" ]]; then
        return 1
    fi
    rel_to_root="${abs_log#"$repo_root"/}"
    if [[ "$rel_to_root" == "$abs_log" ]]; then
        # Did not start with repo_root (defensive — should not happen)
        return 1
    fi

    # Walk commits newest-to-oldest.
    local commits
    commits="$(git -C "$repo_root" log --pretty=format:%H -- "$rel_to_root" 2>/dev/null || true)"
    if [[ -z "$commits" ]]; then
        return 1
    fi

    local chosen_commit="" chosen_content=""
    while IFS= read -r commit; do
        [[ -z "$commit" ]] && continue
        local content
        if ! content="$(git -C "$repo_root" show "${commit}:${rel_to_root}" 2>/dev/null)"; then
            continue
        fi
        if _audit_chain_validates_lines "$content"; then
            chosen_commit="$commit"
            chosen_content="$content"
            break
        fi
    done <<< "$commits"

    if [[ -z "$chosen_commit" ]]; then
        return 1
    fi

    # Rewrite the log to the recovered state + append markers.
    {
        printf '%s\n' "$chosen_content"
        printf '[CHAIN-GAP-RECOVERED-FROM-GIT commit=%s]\n' "${chosen_commit:0:12}"
        printf '[CHAIN-RECOVERED source=git_history commit=%s]\n' "${chosen_commit:0:12}"
    } > "$log_path"
    return 0
}

# -----------------------------------------------------------------------------
# _audit_recover_from_snapshot <log_path> <primitive_id>
# For UNTRACKED chain-critical logs (L1 panel-decisions, L2 cost-budget-events):
# locate latest snapshot at <archive>/<utc-date>-<primitive>.jsonl.gz; verify
# (signature optional in cycle-098 Sprint 1C — daily snapshot job lands later);
# decompress; restore entries; mark gap [CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H]
# + [CHAIN-RECOVERED].
# -----------------------------------------------------------------------------
_audit_recover_from_snapshot() {
    local log_path="$1"
    local primitive_id="$2"

    if [[ -z "$primitive_id" ]]; then
        return 1
    fi

    # Resolve archive directory.
    local archive_dir="${LOA_AUDIT_ARCHIVE_DIR:-${_LOA_AUDIT_REPO_ROOT}/../grimoires/loa/audit-archive}"
    if [[ ! -d "$archive_dir" ]]; then
        return 1
    fi

    # Locate most recent snapshot for the primitive.
    local snapshot
    snapshot="$(ls -1t "${archive_dir}"/*-${primitive_id}.jsonl.gz 2>/dev/null | head -n 1 || true)"
    if [[ -z "$snapshot" || ! -f "$snapshot" ]]; then
        return 1
    fi

    # Decompress snapshot to a temp file (mode 0600).
    local tmp
    tmp="$(mktemp)"
    chmod 600 "$tmp"
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN

    if ! gzip -dc "$snapshot" > "$tmp"; then
        return 1
    fi

    # Validate the snapshot's chain integrity before restoring.
    local snapshot_content
    snapshot_content="$(cat "$tmp")"
    if ! _audit_chain_validates_lines "$snapshot_content"; then
        _audit_log "snapshot at $snapshot has broken chain — refusing to restore"
        return 1
    fi

    # Sprint 2C remediation (audit F3): when a .sig sidecar exists, verify it.
    # Refuse recovery on signature mismatch — an attacker who swaps the .gz with
    # a chain-internally-valid-but-malicious archive is detected here.
    # When LOA_AUDIT_RECOVER_REQUIRE_SIG=1, refuse on missing .sig too
    # (defense-in-depth for high-trust deployments).
    local sig_path="${snapshot}.sig"
    if [[ -f "$sig_path" ]]; then
        local sig_kid sig_b64 sig_sha256
        if ! sig_kid="$(jq -r '.signing_key_id // ""' "$sig_path" 2>/dev/null)" \
            || ! sig_b64="$(jq -r '.signature // ""' "$sig_path" 2>/dev/null)" \
            || ! sig_sha256="$(jq -r '.sha256 // ""' "$sig_path" 2>/dev/null)"; then
            _audit_log "snapshot .sig sidecar at $sig_path is malformed — refusing to restore"
            return 1
        fi
        if [[ -z "$sig_kid" || -z "$sig_b64" || -z "$sig_sha256" ]]; then
            _audit_log "snapshot .sig sidecar at $sig_path missing required fields (signing_key_id/signature/sha256) — refusing to restore"
            return 1
        fi
        local actual_sha256
        actual_sha256="$(_audit_sha256 < "$snapshot")"
        if [[ "$actual_sha256" != "$sig_sha256" ]]; then
            _audit_log "snapshot $snapshot sha256 mismatch with .sig sidecar (got $actual_sha256, expected $sig_sha256) — possible tampering, refusing to restore"
            return 1
        fi
        local pubkey_pem
        if ! pubkey_pem="$(_audit_pubkey_for_key_id "$sig_kid" 2>/dev/null)"; then
            _audit_log "cannot resolve pubkey for signing_key_id=$sig_kid (snapshot .sig at $sig_path) — refusing to restore"
            return 1
        fi
        if ! _audit_verify_signature_inline "$pubkey_pem" "$actual_sha256" "$sig_b64"; then
            _audit_log "snapshot signature verification FAILED for $snapshot (sig_kid=$sig_kid) — refusing to restore"
            return 1
        fi
        _audit_log "snapshot $snapshot signature verified (sig_kid=$sig_kid)"
    elif [[ "${LOA_AUDIT_RECOVER_REQUIRE_SIG:-0}" == "1" ]]; then
        _audit_log "snapshot $snapshot has no .sig sidecar and LOA_AUDIT_RECOVER_REQUIRE_SIG=1 — refusing to restore"
        return 1
    fi

    # Restore: replace log with snapshot content + gap markers + recovered marker.
    local snapshot_basename
    snapshot_basename="$(basename "$snapshot")"
    {
        printf '%s\n' "$snapshot_content"
        printf '[CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H snapshot=%s]\n' "$snapshot_basename"
        printf '[CHAIN-RECOVERED source=snapshot_archive snapshot=%s]\n' "$snapshot_basename"
    } > "$log_path"
    return 0
}

# -----------------------------------------------------------------------------
# audit_recover_chain <log_path>
#
# NFR-R7 hash-chain recovery procedure (SDD §3.4.4).
#
# Two paths:
#   1. TRACKED logs (L4 trust-ledger, L6 INDEX): rebuild from git history.
#   2. UNTRACKED chain-critical logs (L1 panel-decisions, L2 cost-budget-events):
#      restore from latest signed snapshot at audit-archive/<utc-date>-<P>.jsonl.gz.
#
# On rebuild success: write [CHAIN-RECOVERED] marker; resume normal chain.
# On rebuild failure: write [CHAIN-BROKEN] marker; emit BLOCKER for operator;
# degraded mode (reads OK, writes blocked).
#
# Returns 0 on success, non-zero on failure.
# -----------------------------------------------------------------------------
audit_recover_chain() {
    local log_path="$1"
    if [[ -z "$log_path" ]]; then
        _audit_log "audit_recover_chain: missing log_path"
        return 2
    fi

    if [[ ! -f "$log_path" ]]; then
        _audit_log "audit_recover_chain: log file does not exist: $log_path"
        return 2
    fi

    # If chain already validates, nothing to do.
    if audit_verify_chain "$log_path" >/dev/null 2>&1; then
        _audit_log "audit_recover_chain: chain already valid; nothing to do"
        return 0
    fi

    local primitive_id
    primitive_id="$(_audit_primitive_id_for_log "$log_path" 2>/dev/null || echo "")"

    # Try tracked-log recovery first (preferred for L4/L6).
    if _audit_log_is_tracked "$log_path"; then
        if _audit_recover_from_git "$log_path"; then
            _audit_log "audit_recover_chain: recovered from git history (log: $log_path)"
            return 0
        fi
        _audit_log "audit_recover_chain: git-history recovery failed for $log_path"
    fi

    # Fall back to snapshot-archive recovery.
    if [[ -n "$primitive_id" ]]; then
        if _audit_recover_from_snapshot "$log_path" "$primitive_id"; then
            _audit_log "audit_recover_chain: recovered from snapshot archive (log: $log_path, primitive: $primitive_id)"
            return 0
        fi
        _audit_log "audit_recover_chain: snapshot recovery failed for $log_path"
    fi

    # Both failed: emit BLOCKER + write [CHAIN-BROKEN] marker.
    {
        printf '[CHAIN-BROKEN at=%s primitive=%s]\n' \
            "$(_audit_now_iso8601)" \
            "${primitive_id:-unknown}"
    } >> "$log_path"
    _audit_log "BLOCKER: chain recovery failed for $log_path; primitive in degraded mode (reads OK, writes blocked)"
    return 1
}

# -----------------------------------------------------------------------------
# audit_seal_chain <primitive_id> <log_path>
#
# Append a final marker line `[<PRIMITIVE>-DISABLED]` indicating the primitive
# has been sealed (e.g., uninstall, rotation, decommission). The marker is NOT
# a JSON envelope; consumers ignore it for chain walks.
# -----------------------------------------------------------------------------
audit_seal_chain() {
    local primitive_id="$1"
    local log_path="$2"
    if [[ -z "$primitive_id" || -z "$log_path" ]]; then
        _audit_log "audit_seal_chain: missing argument"
        return 2
    fi
    mkdir -p "$(dirname "$log_path")"
    printf '[%s-DISABLED]\n' "$primitive_id" >> "$log_path"
}

# CLI dispatcher.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        emit)
            shift
            audit_emit "$@"
            ;;
        emit-signed)
            shift
            audit_emit_signed "$@"
            ;;
        verify-chain)
            shift
            audit_verify_chain "$@"
            ;;
        verify-trust-store)
            shift
            audit_trust_store_verify "$@"
            ;;
        recover-chain)
            shift
            audit_recover_chain "$@"
            ;;
        seal)
            shift
            audit_seal_chain "$@"
            ;;
        --help|-h|"")
            cat <<EOF
Usage: audit-envelope.sh <command> [args]

Commands:
  emit <primitive_id> <event_type> <payload_json> <log_path>
      Append a validated envelope (signed when LOA_AUDIT_SIGNING_KEY_ID set).
  emit-signed <primitive_id> <event_type> <payload_json> <log_path> [--password-fd N|--password-file PATH]
      Same as emit; signing required (fails if LOA_AUDIT_SIGNING_KEY_ID unset).
  verify-chain <log_path>
      Walk a JSONL log; verify hash-chain + signatures (when present).
  verify-trust-store [<trust-store-path>]
      Verify trust-store root_signature against pinned root pubkey.
  recover-chain <log_path>
      NFR-R7 chain recovery: rebuild from git history (TRACKED logs) or
      restore from snapshot archive (UNTRACKED chain-critical logs).
  seal <primitive_id> <log_path>
      Append [<PRIMITIVE>-DISABLED] marker.
EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            exit 2
            ;;
    esac
fi
