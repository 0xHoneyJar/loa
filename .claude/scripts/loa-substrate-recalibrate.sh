#!/usr/bin/env bash
# =============================================================================
# .claude/scripts/loa-substrate-recalibrate.sh
# =============================================================================
# cycle-109 Sprint 5 T5.6 — operator-gated `loa substrate recalibrate <model-id>`
# CLI shim (FR-1.6 trigger; synchronous-with-progress per C109.OP-5 Q6).
#
# Wraps tools/ceiling-probe.py with:
#   1. Operator-slug verification against OPERATORS.md (C109.OP-5 Q1)
#   2. Canonical model-id parsing (provider:model_id form)
#   3. Synchronous foreground execution with streamed stdout/stderr
#   4. --apply flag passed unconditionally — recalibrate IS the apply
#
# Exit codes:
#   0 — success (calibration applied to model-config.yaml)
#   2 — bad arguments / malformed model-id / missing --operator
#   3 — operator slug not found in OPERATORS.md
#   6 — live probe backend (disabled in cycle-109 substrate-degraded posture)
#   * — bubbles up from tools/ceiling-probe.py (subprocess exit code)
#
# Usage:
#   loa-substrate-recalibrate.sh <model-id> --operator <slug> [opts]
#   loa-substrate-recalibrate.sh anthropic:claude-opus-4-7 \
#       --operator deep-name \
#       --probe-backend fixture \
#       --fixture path/to/probe-trace.json
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CEILING_PROBE="$PROJECT_ROOT/tools/ceiling-probe.py"
OPERATOR_IDENTITY="$PROJECT_ROOT/.claude/scripts/operator-identity.sh"

usage() {
    cat <<'EOF'
Usage: loa substrate recalibrate <model-id> --operator <slug> [opts]

cycle-109 FR-1.6 — empirical ceiling reprobe + apply.

Required:
  <model-id>            provider:model_id form (e.g. anthropic:claude-opus-4-7)
  --operator <slug>     OPERATORS.md slug — gates the destructive recalibrate
                        per C109.OP-5 Q1 (operator-only).

Optional:
  --model-config <path> Path to model-config.yaml (default: .claude/defaults/model-config.yaml)
  --probe-backend MODE  fixture|live  (default fixture; live disabled in cycle-109)
  --fixture <path>      Required when --probe-backend fixture
  --empty-threshold F   Empty-content rate above which a size is unsafe (default 0.05)
  --stale-after-days N  Days before reprobe trigger reactivates (default 30)
  --help, -h            Show this help

Behavior:
  - Synchronous; streams probe progress to stdout
  - On success, model-config.yaml is updated in-place with the new
    effective_input_ceiling and ceiling_calibration block
  - On error, exits with a non-zero code without mutating config
EOF
}

# --- argument parsing -------------------------------------------------------

MODEL_ID=""
OPERATOR=""
MODEL_CONFIG=""
PROBE_BACKEND="fixture"
FIXTURE=""
EMPTY_THRESHOLD=""
STALE_AFTER_DAYS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage; exit 0 ;;
        --operator)
            OPERATOR="${2:-}"; shift 2 ;;
        --model-config)
            MODEL_CONFIG="${2:-}"; shift 2 ;;
        --probe-backend)
            PROBE_BACKEND="${2:-}"; shift 2 ;;
        --fixture)
            FIXTURE="${2:-}"; shift 2 ;;
        --empty-threshold)
            EMPTY_THRESHOLD="${2:-}"; shift 2 ;;
        --stale-after-days)
            STALE_AFTER_DAYS="${2:-}"; shift 2 ;;
        --)
            shift; break ;;
        -*)
            echo "error: unknown flag $1" >&2
            usage >&2
            exit 2 ;;
        *)
            if [[ -z "$MODEL_ID" ]]; then
                MODEL_ID="$1"
                shift
            else
                echo "error: unexpected positional argument: $1" >&2
                usage >&2
                exit 2
            fi
            ;;
    esac
done

# --- validation -------------------------------------------------------------

if [[ -z "$MODEL_ID" ]]; then
    echo "error: missing <model-id> positional argument" >&2
    usage >&2
    exit 2
fi

if [[ -z "$OPERATOR" ]]; then
    echo "error: missing --operator <slug> (operator-gated per C109.OP-5 Q1)" >&2
    exit 2
fi

# Canonical model-id format: provider:model_id
if [[ "$MODEL_ID" != *:* ]]; then
    echo "error: <model-id> must be in provider:model_id format (got: '$MODEL_ID')" >&2
    exit 2
fi
PROVIDER="${MODEL_ID%%:*}"
MODEL_ONLY="${MODEL_ID#*:}"

if [[ -z "$PROVIDER" || -z "$MODEL_ONLY" ]]; then
    echo "error: malformed model-id; expected provider:model_id (got: '$MODEL_ID')" >&2
    exit 2
fi

# Default model-config path
if [[ -z "$MODEL_CONFIG" ]]; then
    MODEL_CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
fi

if [[ ! -f "$MODEL_CONFIG" ]]; then
    echo "error: model-config not found: $MODEL_CONFIG" >&2
    exit 2
fi

if [[ ! -f "$CEILING_PROBE" ]]; then
    echo "error: ceiling-probe.py not found at $CEILING_PROBE" >&2
    exit 2
fi

# --- operator verification (C109.OP-5 Q1: OPERATORS.md slug gated) ----------

if [[ -f "$OPERATOR_IDENTITY" ]]; then
    # shellcheck source=/dev/null
    # operator-identity.sh requires set -u tolerance — source defensively.
    set +u
    if ! source "$OPERATOR_IDENTITY" 2>/dev/null; then
        set -u
        echo "error: failed to source operator-identity helper" >&2
        exit 3
    fi
    set -u
    if ! operator_identity_verify "$OPERATOR" >/dev/null 2>&1; then
        echo "error: operator slug '$OPERATOR' not verified in OPERATORS.md" >&2
        echo "       (cycle-109 Q1: recalibrate is operator-only; add yourself to" >&2
        echo "        grimoires/loa/operators.md or supply a known slug)" >&2
        exit 3
    fi
else
    # operator-identity.sh not present — refuse on safety grounds rather than
    # silently bypassing the gate.
    echo "warning: operator-identity.sh not present at $OPERATOR_IDENTITY — gate cannot verify" >&2
    echo "error: refusing to recalibrate without operator-identity verification" >&2
    exit 3
fi

# --- live-backend gate (cycle-109 substrate-degraded posture) ---------------

if [[ "$PROBE_BACKEND" == "live" ]]; then
    echo "error: --probe-backend live is DISABLED in cycle-109 (substrate-degraded)" >&2
    echo "       Live calibration is operator-driven; see C109.OP-6 + runbook:" >&2
    echo "       grimoires/loa/cycles/cycle-109-substrate-hardening/operator-approval.md" >&2
    exit 6
fi

if [[ "$PROBE_BACKEND" == "fixture" && -z "$FIXTURE" ]]; then
    echo "error: --probe-backend fixture requires --fixture <path>" >&2
    exit 2
fi

# --- run the probe ----------------------------------------------------------

echo "[recalibrate] model=$MODEL_ID  operator=$OPERATOR  backend=$PROBE_BACKEND"
echo "[recalibrate] config=$MODEL_CONFIG"

PROBE_ARGS=(
    "$CEILING_PROBE"
    --provider "$PROVIDER"
    --model-id "$MODEL_ONLY"
    --model-config "$MODEL_CONFIG"
    --probe-backend "$PROBE_BACKEND"
    --apply
)
if [[ -n "$FIXTURE" ]]; then
    PROBE_ARGS+=(--fixture "$FIXTURE")
fi
if [[ -n "$EMPTY_THRESHOLD" ]]; then
    PROBE_ARGS+=(--empty-threshold "$EMPTY_THRESHOLD")
fi
if [[ -n "$STALE_AFTER_DAYS" ]]; then
    PROBE_ARGS+=(--stale-after-days "$STALE_AFTER_DAYS")
fi

# Synchronous, streamed — operator-driven per C109.OP-5 Q6.
python3 "${PROBE_ARGS[@]}"
rc=$?

if [[ "$rc" -eq 0 ]]; then
    echo "[recalibrate] OK — calibration applied"
else
    echo "[recalibrate] FAILED — ceiling-probe.py exit=$rc" >&2
fi
exit "$rc"
