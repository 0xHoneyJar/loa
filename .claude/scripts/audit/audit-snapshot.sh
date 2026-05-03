#!/usr/bin/env bash
# =============================================================================
# audit-snapshot.sh — Daily snapshot of UNTRACKED chain-critical audit logs
#
# cycle-098 Sprint 2C — RPO 24h for L1/L2 per SDD §3.4.4 ↔ §3.7 reconciliation
# (formerly weekly per Flatline pass #4 SKP-001 MUTUAL HIGH).
#
# Reads .claude/data/audit-retention-policy.yaml for the list of primitives
# where chain_critical=true AND git_tracked=false. For each:
#   1. Locate the rolling log at .run/<log_basename>
#   2. Verify chain integrity (audit_verify_chain)
#   3. Compress to grimoires/loa/audit-archive/<utc-date>-<primitive>.jsonl.gz
#   4. Optionally sign (when LOA_AUDIT_SIGNING_KEY_ID is set) — produces a
#      <archive>.sig sidecar containing base64(Ed25519(sha256(<archive>)))
#
# The archive directory is git-tracked. Operators commit the archives in their
# regular workflow. The recovery path (audit_recover_chain) consumes these.
#
# Subcommands / flags:
#   --dry-run               Print intent only; no file writes
#   --primitive <id>        Snapshot a single primitive (e.g., L1, L2)
#   --policy <yaml-path>    Override retention-policy yaml location
#   --archive-dir <path>    Override output archive directory
#   --logs-dir <path>       Override .run/ rolling-log directory
#   --help, -h              Show usage
#
# Exit codes:
#   0  success (or all primitives skipped — already-snapshotted today)
#   1  any primitive's snapshot failed
#   2  invalid arguments
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/../../.." && pwd)"

usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit 0
}

DRY_RUN=0
SCOPE_PRIMITIVE=""
POLICY_FILE="${LOA_AUDIT_RETENTION_POLICY:-${_REPO_ROOT}/.claude/data/audit-retention-policy.yaml}"
ARCHIVE_DIR="${LOA_AUDIT_ARCHIVE_DIR:-${_REPO_ROOT}/grimoires/loa/audit-archive}"
LOGS_DIR="${LOA_AUDIT_LOGS_DIR:-${_REPO_ROOT}/.run}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --primitive) SCOPE_PRIMITIVE="$2"; shift 2 ;;
        --policy) POLICY_FILE="$2"; shift 2 ;;
        --archive-dir) ARCHIVE_DIR="$2"; shift 2 ;;
        --logs-dir) LOGS_DIR="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Source audit-envelope.sh to access audit_verify_chain.
# shellcheck source=../audit-envelope.sh
source "${_REPO_ROOT}/.claude/scripts/audit-envelope.sh"

_log() { echo "[audit-snapshot] $*" >&2; }

# ---------------------------------------------------------------------------
# Read snapshot-eligible primitives from policy file:
# - chain_critical: true
# - git_tracked: false
# Returns lines of "<id>:<log_basename>".
# ---------------------------------------------------------------------------
read_eligible_primitives() {
    if [[ ! -f "$POLICY_FILE" ]]; then
        _log "policy file missing: $POLICY_FILE"
        return 1
    fi
    if command -v yq >/dev/null 2>&1; then
        yq -r '
          .primitives | to_entries[]
          | select(.value.chain_critical == true and .value.git_tracked == false)
          | "\(.key):\(.value.log_basename)"
        ' "$POLICY_FILE"
        return $?
    fi
    python3 - "$POLICY_FILE" <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.stderr.write("yq not in PATH and PyYAML not installed; cannot read policy\n")
    sys.exit(2)
with open(sys.argv[1]) as f:
    doc = yaml.safe_load(f) or {}
for pid, attrs in (doc.get("primitives") or {}).items():
    if (attrs or {}).get("chain_critical") and not (attrs or {}).get("git_tracked"):
        print(f"{pid}:{attrs['log_basename']}")
PY
}

# ---------------------------------------------------------------------------
# Compute UTC day in YYYY-MM-DD form, allowing test override via
# LOA_AUDIT_SNAPSHOT_TEST_DAY.
# ---------------------------------------------------------------------------
utc_day() {
    if [[ -n "${LOA_AUDIT_SNAPSHOT_TEST_DAY:-}" ]]; then
        echo "$LOA_AUDIT_SNAPSHOT_TEST_DAY"
    else
        date -u +%Y-%m-%d
    fi
}

# ---------------------------------------------------------------------------
# snapshot_one <primitive_id> <log_basename>
# Returns:
#   0  success (snapshot written or already-existing)
#   1  failure
#   2  source log missing (not an error per se — primitive may not be active)
# ---------------------------------------------------------------------------
snapshot_one() {
    local primitive_id="$1"
    local log_basename="$2"
    local source_log="${LOGS_DIR}/${log_basename}"
    local day archive
    day="$(utc_day)"
    archive="${ARCHIVE_DIR}/${day}-${primitive_id}.jsonl.gz"

    if [[ ! -f "$source_log" ]]; then
        _log "skip: source log missing for $primitive_id at $source_log"
        return 2
    fi

    # Idempotency: if archive already exists for this UTC day, skip.
    if [[ -f "$archive" ]]; then
        _log "skip: archive exists for $primitive_id on $day at $archive"
        return 0
    fi

    # Verify source chain before snapshotting (refuse to archive a broken chain).
    if ! audit_verify_chain "$source_log" >/dev/null 2>&1; then
        _log "ERROR: chain verification failed for $primitive_id at $source_log — refusing to snapshot"
        return 1
    fi

    if (( DRY_RUN )); then
        _log "DRY-RUN: would write $archive (gzip $source_log)"
        return 0
    fi

    mkdir -p "$ARCHIVE_DIR"
    # Atomically write via temp + rename.
    local tmp
    tmp="$(mktemp "${archive}.XXXXXX.tmp")"
    if ! gzip -c "$source_log" > "$tmp"; then
        _log "ERROR: gzip failed for $source_log"
        rm -f "$tmp"
        return 1
    fi
    chmod 644 "$tmp"
    mv "$tmp" "$archive"
    _log "wrote: $archive ($(wc -c < "$archive") bytes)"

    # Optional Ed25519 sidecar signature when signing key is configured.
    if [[ -n "${LOA_AUDIT_SIGNING_KEY_ID:-}" ]]; then
        local sig_path="${archive}.sig"
        local archive_sha256
        archive_sha256="$(_audit_sha256 < "$archive")"
        local pw_args=()
        if [[ -n "${LOA_AUDIT_FORWARD_PW_ARGS+set}" ]]; then
            pw_args=(${LOA_AUDIT_FORWARD_PW_ARGS[@]+"${LOA_AUDIT_FORWARD_PW_ARGS[@]}"})
        fi
        local sig_b64
        if sig_b64="$(printf '%s' "$archive_sha256" | _audit_sign_stdin "$LOA_AUDIT_SIGNING_KEY_ID" ${pw_args[@]+"${pw_args[@]}"})"; then
            jq -nc \
                --arg kid "$LOA_AUDIT_SIGNING_KEY_ID" \
                --arg sha256 "$archive_sha256" \
                --arg sig "$sig_b64" \
                --arg ts "$(_audit_now_iso8601)" \
                --arg primitive "$primitive_id" \
                --arg day "$day" \
                '{
                    schema_version: "1.0",
                    primitive_id: $primitive,
                    utc_day: $day,
                    sha256: $sha256,
                    signing_key_id: $kid,
                    signed_at: $ts,
                    signature: $sig
                }' > "$sig_path"
            chmod 644 "$sig_path"
            _log "signed: $sig_path"
        else
            _log "WARNING: signing failed for $archive (key_id=$LOA_AUDIT_SIGNING_KEY_ID); archive written unsigned"
        fi
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Main loop.
# ---------------------------------------------------------------------------
overall=0
total_attempted=0
total_succeeded=0
total_skipped=0

while IFS=: read -r pid basename; do
    [[ -z "$pid" ]] && continue
    if [[ -n "$SCOPE_PRIMITIVE" && "$pid" != "$SCOPE_PRIMITIVE" ]]; then
        continue
    fi
    total_attempted=$((total_attempted + 1))
    rc=0
    snapshot_one "$pid" "$basename" || rc=$?
    case "$rc" in
        0) total_succeeded=$((total_succeeded + 1)) ;;
        2) total_skipped=$((total_skipped + 1)) ;;
        *) overall=1 ;;
    esac
done < <(read_eligible_primitives)

_log "summary: attempted=$total_attempted succeeded=$total_succeeded skipped=$total_skipped failed=$((total_attempted - total_succeeded - total_skipped))"
exit "$overall"
