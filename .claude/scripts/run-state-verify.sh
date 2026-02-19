#!/usr/bin/env bash
# run-state-verify.sh — HMAC-SHA256 verification for run state files (FR-5)
#
# Subcommands:
#   init    <run_id>       — Generate per-run HMAC key
#   sign    <file> <run_id> — Sign a state JSON file
#   verify  <file>          — Verify a signed state file
#   cleanup [--stale --max-age 7d] — Remove orphaned keys
#
# Exit codes:
#   0 — Verified / success
#   1 — Tampered / verification failed
#   2 — Unsigned (missing key or no HMAC fields)
#   3 — Usage error
set -euo pipefail

# ── Constants ──────────────────────────────────────────

KEY_DIR="${HOME}/.claude/.run-keys"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helpers ────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 3; }

# Verify file safety: trusted base directory, no symlinks, ownership, permissions
verify_file_safety() {
  local file="$1"
  local real_path

  # Resolve to absolute path
  real_path="$(realpath "$file" 2>/dev/null)" || die "Cannot resolve path: $file"

  # Get trusted base directory from git root
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Not in a git repository"
  local trusted_base="${git_root}/.run"

  # Check file is under trusted base
  case "$real_path" in
    "${trusted_base}"/*) ;; # OK
    *) echo "REJECTED: $file is outside trusted base directory ${trusted_base}" >&2; return 1 ;;
  esac

  # Symlink detection
  if [ -L "$file" ]; then
    echo "REJECTED: $file is a symlink" >&2
    return 1
  fi

  # Ownership check (current user)
  local file_uid
  file_uid="$(stat -c '%u' "$file" 2>/dev/null)" || file_uid="$(stat -f '%u' "$file" 2>/dev/null)"
  local my_uid
  my_uid="$(id -u)"
  if [ "$file_uid" != "$my_uid" ]; then
    echo "REJECTED: $file owned by uid $file_uid, expected $my_uid" >&2
    return 1
  fi

  # Permission check: no world-write, no setuid/setgid
  local perms
  perms="$(stat -c '%a' "$file" 2>/dev/null)" || perms="$(stat -f '%Lp' "$file" 2>/dev/null)"
  case "$perms" in
    600|640|644|660|664) ;; # OK — owner/group readable, no world-write
    *) echo "REJECTED: $file has permissions $perms, expected 600/640/644/660/664" >&2; return 1 ;;
  esac

  return 0
}

# Canonicalize JSON: sort keys, remove HMAC fields
canonicalize() {
  local file="$1"
  jq -cS 'del(._hmac, ._key_id)' "$file"
}

# ── Subcommands ────────────────────────────────────────

cmd_init() {
  local run_id="${1:-}"
  [ -z "$run_id" ] && die "Usage: $0 init <run_id>"

  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"

  local key_path="${KEY_DIR}/${run_id}.key"
  if [ -f "$key_path" ]; then
    echo "Key already exists for run_id: $run_id" >&2
    return 0
  fi

  openssl rand -hex 32 > "$key_path"
  chmod 600 "$key_path"
  echo "Key generated: $key_path"
}

cmd_sign() {
  local file="${1:-}"
  local run_id="${2:-}"
  [ -z "$file" ] || [ -z "$run_id" ] && die "Usage: $0 sign <file> <run_id>"
  [ -f "$file" ] || die "File not found: $file"

  local key_path="${KEY_DIR}/${run_id}.key"
  if [ ! -f "$key_path" ]; then
    echo "No key for run_id $run_id — generating" >&2
    cmd_init "$run_id"
  fi

  local key
  key="$(cat "$key_path")"

  # Canonicalize (strip existing HMAC fields if re-signing)
  local canonical
  canonical="$(canonicalize "$file")"

  # Compute HMAC-SHA256
  local hmac
  hmac="$(echo -n "$canonical" | openssl dgst -sha256 -hmac "$key" -hex 2>/dev/null | awk '{print $NF}')"

  # Add _hmac and _key_id to the file (preserve original permissions)
  local tmp="${file}.tmp.$$"
  local orig_perms
  orig_perms="$(stat -c '%a' "$file" 2>/dev/null)" || orig_perms="$(stat -f '%Lp' "$file" 2>/dev/null)" || orig_perms="644"
  jq --arg hmac "$hmac" --arg key_id "$run_id" \
    '. + {"_hmac": $hmac, "_key_id": $key_id}' "$file" > "$tmp"
  chmod "$orig_perms" "$tmp"
  mv "$tmp" "$file"

  echo "Signed: $file (key_id: $run_id)"
}

cmd_verify() {
  local file="${1:-}"
  [ -z "$file" ] && die "Usage: $0 verify <file>"
  [ -f "$file" ] || die "File not found: $file"

  # Safety checks
  if ! verify_file_safety "$file"; then
    exit 1
  fi

  # Check for HMAC fields
  local stored_hmac stored_key_id
  stored_hmac="$(jq -r '._hmac // empty' "$file")"
  stored_key_id="$(jq -r '._key_id // empty' "$file")"

  if [ -z "$stored_hmac" ] || [ -z "$stored_key_id" ]; then
    echo "UNSIGNED: No _hmac or _key_id in $file" >&2
    exit 2
  fi

  # Find key
  local key_path="${KEY_DIR}/${stored_key_id}.key"
  if [ ! -f "$key_path" ]; then
    echo "UNSIGNED: Key not found for key_id $stored_key_id (missing key — interactive recovery needed)" >&2
    exit 2
  fi

  local key
  key="$(cat "$key_path")"

  # Canonicalize and compute expected HMAC
  local canonical
  canonical="$(canonicalize "$file")"

  local expected_hmac
  expected_hmac="$(echo -n "$canonical" | openssl dgst -sha256 -hmac "$key" -hex 2>/dev/null | awk '{print $NF}')"

  # Compare
  if [ "$stored_hmac" = "$expected_hmac" ]; then
    echo "VERIFIED: $file (key_id: $stored_key_id)"
    exit 0
  else
    echo "TAMPERED: $file — HMAC mismatch" >&2
    exit 1
  fi
}

cmd_cleanup() {
  local stale=false
  local max_age="7d"

  while [ $# -gt 0 ]; do
    case "$1" in
      --stale) stale=true; shift ;;
      --max-age) max_age="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  [ ! -d "$KEY_DIR" ] && { echo "No keys directory"; return 0; }

  if [ "$stale" = true ]; then
    # Parse max_age (supports Nd format)
    local days
    days="$(echo "$max_age" | sed 's/d$//')"
    [ -z "$days" ] && die "Invalid max-age: $max_age"

    local count=0
    find "$KEY_DIR" -name '*.key' -mtime "+${days}" -print0 2>/dev/null | \
      while IFS= read -r -d '' keyfile; do
        rm -f "$keyfile"
        count=$((count + 1))
        echo "Removed stale key: $(basename "$keyfile")"
      done
    echo "Cleanup complete"
  else
    # Remove all keys
    local count
    count="$(find "$KEY_DIR" -name '*.key' 2>/dev/null | wc -l)"
    rm -f "${KEY_DIR}"/*.key 2>/dev/null || true
    echo "Removed $count key(s)"
  fi
}

# ── Main ───────────────────────────────────────────────

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    init)    cmd_init "$@" ;;
    sign)    cmd_sign "$@" ;;
    verify)  cmd_verify "$@" ;;
    cleanup) cmd_cleanup "$@" ;;
    *)       die "Usage: $0 {init|sign|verify|cleanup} [args...]" ;;
  esac
}

main "$@"
