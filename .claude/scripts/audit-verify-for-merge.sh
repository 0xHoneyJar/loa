#!/usr/bin/env bash
# =============================================================================
# audit-verify-for-merge.sh — operator-opt-in, FAIL-CLOSED audit merge gate
#
# OKF/ICM adoption cycle, Sprint 9 (rec #2, agent-doable half). Runs the STRICT
# "verify-for-merge" chain verification (audit-envelope.sh --verify-for-merge)
# over the MODELINV log (+ any extra logs) and FAILS CLOSED (non-zero) on a
# BOOTSTRAP-PENDING/INVALID trust-store, a missing trust-store, a producer-writable
# local-pubkey-only writer key, or a post-cutoff strip-attack.
#
# DEFAULT OFF. It is inert unless LOA_AUDIT_VERIFY_FOR_MERGE=1. This is deliberate:
# the trust-store is currently BOOTSTRAP-PENDING and CANNOT be activated by an agent
# — the maintainer trust-store ceremony (offline root-sign + enable signing +
# grandfather the cutoff) must complete FIRST, or every merge hard-fails by design.
# Activation runbook: grimoires/loa/runbooks/audit-verify-for-merge-activation.md
#
# Usage:  audit-verify-for-merge.sh [extra-log ...]
# Env:    LOA_AUDIT_VERIFY_FOR_MERGE=1   enable the gate (default: disabled → exit 0)
#         LOA_AUDIT_MERGE_LOGS="a,b,c"   override the default log set (CSV, repo-relative)
# Exit:   0 = disabled OR all chains pass strict ; 1 = fail-closed ; 2 = usage/env error
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
AENV="${SCRIPT_DIR}/audit-envelope.sh"

if [[ "${LOA_AUDIT_VERIFY_FOR_MERGE:-0}" != "1" ]]; then
  echo "[audit-gate] opt-in gate DISABLED — set LOA_AUDIT_VERIFY_FOR_MERGE=1 to enable (only AFTER the maintainer trust-store ceremony; see audit-verify-for-merge-activation.md)" >&2
  exit 0
fi
[[ -f "$AENV" ]] || { echo "[audit-gate] audit-envelope.sh not found: $AENV" >&2; exit 2; }

# Default log set: the MODELINV chain. Override via LOA_AUDIT_MERGE_LOGS (CSV).
declare -a LOGS
if [[ -n "${LOA_AUDIT_MERGE_LOGS:-}" ]]; then
  IFS=',' read -r -a LOGS <<< "${LOA_AUDIT_MERGE_LOGS}"
else
  LOGS=(".run/model-invoke.jsonl")
fi
# extra logs from argv
LOGS+=("$@")

rc=0 checked=0
for rel in "${LOGS[@]+"${LOGS[@]}"}"; do
  [[ -n "$rel" ]] || continue
  case "$rel" in /*) full="$rel" ;; *) full="${PROJECT_ROOT}/${rel}" ;; esac
  [[ -f "$full" ]] || { echo "[audit-gate] skip (absent): $rel" >&2; continue; }
  checked=$((checked + 1))
  if bash "$AENV" verify-chain --verify-for-merge "$full"; then
    echo "[audit-gate] PASS strict verify-for-merge: $rel" >&2
  else
    echo "[audit-gate] FAIL-CLOSED: $rel did not pass strict verify-for-merge" >&2
    rc=1
  fi
done

if [[ $rc -ne 0 ]]; then
  exit $rc
fi
if [[ $checked -eq 0 ]]; then
  # Don't pass silently when there was nothing to check — surface it loudly so an
  # absent/renamed MODELINV log can't read as a green gate.
  echo "[audit-gate] WARNING: no target audit chain found to verify (nothing checked) — confirm LOA_AUDIT_MERGE_LOGS / .run/model-invoke.jsonl is present" >&2
  exit 0
fi
echo "[audit-gate] OK — ${checked} chain(s) passed strict verify-for-merge" >&2
exit 0
