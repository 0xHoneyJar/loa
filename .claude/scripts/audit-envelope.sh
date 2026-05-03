#!/usr/bin/env bash
# =============================================================================
# audit-envelope.sh — canonical write/read/verify path for L1-L7 audit logs.
#
# cycle-098 Sprint 1A foundation. All 7 primitives' JSONL audit logs use the
# same envelope shape from `.claude/data/trajectory-schemas/agent-network-envelope.schema.json`.
#
# Sprint 1A implements:
#   - audit_emit            : append a validated, hash-chained envelope
#   - audit_verify_chain    : walk a log; verify prev_hash continuity
#   - audit_seal_chain      : write final [<PRIMITIVE>-DISABLED] marker
#
# Sprint 1B will add (TODO markers below):
#   - Ed25519 signing on emit (via cryptography)
#   - Ed25519 signature verification in verify_chain
#   - Key loading from ~/.config/loa/audit-keys/<signing_key_id>.priv
#   - LOA_AUDIT_KEY_PASSWORD --password-fd / --password-file support (SKP-002)
#
# Sprint 1C: sanitize_for_session_start integration (untrusted-content fields).
# Sprint 1D: L1 panel-decisions integration.
#
# Conventions:
#   - Canonical-JSON via lib/jcs.sh (RFC 8785). NEVER substitute jq -S -c.
#   - Schema validation at write-time via ajv (Node) or jsonschema (Python fallback).
#   - JSONL: one envelope per line, no whitespace, terminated with \n.
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

# Source JCS canonicalizer.
# shellcheck source=../../lib/jcs.sh
source "${_LOA_AUDIT_JCS_LIB}"

# Schema version this writer emits. Bump major on breaking schema change.
LOA_AUDIT_SCHEMA_VERSION="${LOA_AUDIT_SCHEMA_VERSION:-1.0.0}"

# -----------------------------------------------------------------------------
# _audit_log() — internal logging helper. Goes to stderr to avoid corrupting stdout.
# -----------------------------------------------------------------------------
_audit_log() {
    echo "[audit-envelope] $*" >&2
}

# -----------------------------------------------------------------------------
# _audit_now_iso8601() — produce microsecond-precision UTC ISO-8601 timestamp.
# Format: 2026-05-02T14:30:00.123456Z
# Cross-platform: GNU date supports %N (nanoseconds); macOS does not.
# -----------------------------------------------------------------------------
_audit_now_iso8601() {
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
# audit_emit <primitive_id> <event_type> <payload_json> <log_path>
#
# Build a validated envelope, append (atomically) to <log_path> as JSONL.
# Computes prev_hash from the existing log; assigns ts_utc; validates schema.
#
# TODO(Sprint 1B): Ed25519-sign the chain-input bytes. For now, signature/
# signing_key_id are omitted (schema allows missing — they're not in `required`).
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

    # Validate payload is JSON object.
    if ! printf '%s' "$payload_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
        _audit_log "audit_emit: payload must be a JSON object"
        return 2
    fi

    # Ensure parent dir exists.
    local log_dir
    log_dir="$(dirname "$log_path")"
    mkdir -p "$log_dir"

    local ts_utc prev_hash
    ts_utc="$(_audit_now_iso8601)"
    prev_hash="$(_audit_compute_prev_hash "$log_path")"

    # Build envelope (signature + signing_key_id deferred to Sprint 1B).
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

    # Validate against schema.
    if ! _audit_validate_envelope "$envelope"; then
        _audit_log "audit_emit: schema validation failed for primitive=$primitive_id event=$event_type"
        return 1
    fi

    # Append atomically. We use a single >> with the full line — for cross-process
    # safety with concurrent writers, callers should hold a flock on the log dir.
    # TODO(Sprint 1B): standardize flock acquisition per primitive.
    printf '%s\n' "$envelope" >> "$log_path"
}

# -----------------------------------------------------------------------------
# audit_verify_chain <log_path>
#
# Walk the JSONL log; verify each entry's prev_hash matches the SHA-256 of the
# canonicalized chain-input of the previous entry. First entry must have
# prev_hash == "GENESIS".
#
# TODO(Sprint 1B): also verify Ed25519 signature against signing_key_id pubkey
# from the trust-store.
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

    local lineno=0
    local expected_prev="GENESIS"
    local count=0
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
        # Compute hash of THIS entry's chain-input for the next iteration.
        expected_prev="$(_audit_chain_input "$line" | _audit_sha256)"
        count=$((count + 1))
    done < "$log_path"

    echo "OK $count entries"
    return 0
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
        verify-chain)
            shift
            audit_verify_chain "$@"
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
      Append a validated envelope (signed in Sprint 1B).
  verify-chain <log_path>
      Walk a JSONL log; verify hash-chain continuity.
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
