#!/usr/bin/env bash
# =============================================================================
# cycle108-update-golden-pins.sh — Cycle-108 sprint-1 T1.G
# =============================================================================
# Atomic compute-sha → audit_emit_signed → write pins → commit flow for the
# golden-pins.json file used by the rollback trace-comparison test
# (tests/integration/rollback-trace-comparison.bats).
#
# Closes SDD §21.3 (Flatline IMP-009 — golden-pins operational spec) and
# pairs with SDD §7 (FR-7 IMP-010 trace-comparison rollback test).
#
# Operator action required: this script invokes audit_emit_signed which
# REQUIRES the L1 signing key to be configured (see audit-keys-bootstrap.md
# runbook). When the key is absent, the script falls back to writing an
# UNSIGNED pins file and emits a stderr WARN; this is acceptable for
# pre-cycle-108-shipping development but T3.A.OP requires the operator to
# re-run this script with their tag-signing key to produce the canonical
# signed artifact for benchmark gating.
#
# Usage:
#   tools/cycle108-update-golden-pins.sh
#   tools/cycle108-update-golden-pins.sh --pin-id rollback-trace
#   tools/cycle108-update-golden-pins.sh --check     # verify only, no write
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/cycle-108"
PINS_JSON="$FIXTURES_DIR/golden-pins.json"
PINS_AUDIT="$FIXTURES_DIR/golden-pins.audit.jsonl"
TRACE_FILE="$FIXTURES_DIR/golden-rollback-trace.modelinv"

PIN_ID="rollback-trace"
MODE="update"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pin-id) PIN_ID="$2"; shift 2 ;;
        --check)  MODE="check"; shift ;;
        -h|--help)
            sed -n '4,30p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$FIXTURES_DIR"

# --- compute sha of trace file ----------------------------------------------
if [[ ! -f "$TRACE_FILE" ]]; then
    echo "[golden-pins] ERROR: trace file missing: $TRACE_FILE" >&2
    echo "[golden-pins] Generate via a baseline replay run first (T1.J integration test produces a template; or hand-craft per SDD §7)." >&2
    exit 1
fi

trace_sha=$(sha256sum "$TRACE_FILE" | awk '{print $1}')
now_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- check mode: verify only ------------------------------------------------
if [[ "$MODE" == "check" ]]; then
    if [[ ! -f "$PINS_JSON" ]]; then
        echo "[golden-pins] ERROR: pins file missing: $PINS_JSON" >&2
        exit 1
    fi
    expected_sha=$(jq -r --arg pin "$PIN_ID" '.pins[$pin].sha256' "$PINS_JSON")
    if [[ "$expected_sha" != "$trace_sha" ]]; then
        echo "[golden-pins] PIN MISMATCH for $PIN_ID:" >&2
        echo "  expected: $expected_sha" >&2
        echo "  actual:   $trace_sha" >&2
        exit 1
    fi
    echo "[golden-pins] OK: $PIN_ID sha matches ($trace_sha)"
    exit 0
fi

# --- update mode: compute pin, optionally sign, write ----------------------

# Try to load audit-envelope helpers
SIGNED=false
operator_key_id="${LOA_AUDIT_SIGNING_KEY_ID:-OPERATOR-UNSIGNED}"

if [[ -f "$PROJECT_ROOT/.claude/scripts/audit-envelope.sh" ]]; then
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.claude/scripts/audit-envelope.sh" 2>/dev/null || true
    if declare -F audit_emit_signed > /dev/null 2>&1; then
        # Signing function is available — attempt to use it
        signing_payload=$(jq -n \
            --arg pin_id "$PIN_ID" \
            --arg sha "$trace_sha" \
            --arg ts "$now_utc" \
            '{pin_id: $pin_id, sha256: $sha, signed_at: $ts}')
        if audit_emit_signed "BASELINES" "golden-pins.signed" "$signing_payload" "$PINS_AUDIT" 2>/dev/null; then
            SIGNED=true
        fi
    fi
fi

if [[ "$SIGNED" != "true" ]]; then
    echo "[golden-pins] WARN: audit_emit_signed unavailable or failed; writing UNSIGNED pin." >&2
    echo "[golden-pins] WARN: T3.A.OP requires operator to re-run this with L1 signing key configured." >&2
fi

# --- write/update golden-pins.json ------------------------------------------

# Read existing pins or initialize
if [[ -f "$PINS_JSON" ]]; then
    existing=$(cat "$PINS_JSON")
else
    existing='{"schema_version": 1, "pins": {}}'
fi

updated=$(echo "$existing" | jq \
    --arg pin "$PIN_ID" \
    --arg fixture "$(realpath --relative-to="$PROJECT_ROOT" "$TRACE_FILE")" \
    --arg sha "$trace_sha" \
    --arg key_id "$operator_key_id" \
    --arg ts "$now_utc" \
    --arg rotation "operator-triggered; no automatic expiration" \
    --argjson signed "$SIGNED" \
    '.pins[$pin] = {
        fixture_path: $fixture,
        sha256: $sha,
        signed_by_key_id: $key_id,
        signed: $signed,
        signed_at: $ts,
        rotation_policy: $rotation,
        last_verified_at: $ts
    }')

# Atomic write
tmp_file=$(mktemp "$PINS_JSON.XXXXXX")
echo "$updated" | jq '.' > "$tmp_file"
mv "$tmp_file" "$PINS_JSON"

echo "[golden-pins] Updated $PINS_JSON"
echo "[golden-pins] Pin: $PIN_ID sha256=$trace_sha signed=$SIGNED"
if [[ "$SIGNED" != "true" ]]; then
    exit 0   # WARN but exit clean — operator follow-up required
fi
echo "[golden-pins] Audit chain: $PINS_AUDIT"
