#!/usr/bin/env bash
# construct-workflow-activate.sh — Manage construct workflow state
# Part of: Construct-Aware Constraint Yielding (cycle-029, FR-2 + FR-5)
#
# Usage:
#   construct-workflow-activate.sh activate --construct <name> --slug <slug> --manifest <path>
#   construct-workflow-activate.sh deactivate [--complete <sprint_id>]
#   construct-workflow-activate.sh check
#   construct-workflow-activate.sh gate <gate_name>
#
# Exit codes:
#   0 — Success (or active workflow found)
#   1 — No active workflow / not active
#   2 — Validation error
set -euo pipefail

# ── Constants ──────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_FILE="${LOA_CONSTRUCT_STATE_FILE:-${REPO_ROOT}/.run/construct-workflow.json}"
AUDIT_LOG="${LOA_CONSTRUCT_AUDIT_LOG:-${REPO_ROOT}/.run/audit.jsonl}"
READER="${SCRIPT_DIR}/construct-workflow-read.sh"

# Allowed pack path prefix (security invariant)
# Env override for testing only — production uses repo-relative default
PACKS_PREFIX="${LOA_PACKS_PREFIX:-${REPO_ROOT}/.claude/constructs/packs/}"

# ── Helpers ────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 2; }

log_audit() {
  local event_json="$1"
  mkdir -p "$(dirname "$AUDIT_LOG")"
  echo "$event_json" >> "$AUDIT_LOG" 2>/dev/null || true
}

# ── Subcommands ────────────────────────────────────────

cmd_activate() {
  local construct="" slug="" manifest=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --construct) construct="$2"; shift 2 ;;
      --slug)      slug="$2"; shift 2 ;;
      --manifest)  manifest="$2"; shift 2 ;;
      *)           die "Unknown option: $1" ;;
    esac
  done

  [[ -z "$construct" ]] && die "Missing --construct <name>"
  [[ -z "$slug" ]]      && die "Missing --slug <slug>"
  [[ -z "$manifest" ]]  && die "Missing --manifest <path>"

  # Security: verify manifest is within allowed packs directory
  local real_manifest
  real_manifest="$(realpath "$manifest" 2>/dev/null)" || die "Cannot resolve manifest path: $manifest"
  local real_prefix
  real_prefix="$(realpath "$PACKS_PREFIX" 2>/dev/null)" || die "Cannot resolve packs prefix"

  if [[ "$real_manifest" != "$real_prefix"* ]]; then
    die "Manifest must be within $PACKS_PREFIX (got: $real_manifest)"
  fi

  # Read and validate workflow via reader
  local workflow
  workflow=$("$READER" "$manifest") || {
    local rc=$?
    if [[ $rc -eq 1 ]]; then
      die "No workflow section in manifest: $manifest"
    else
      die "Validation error reading manifest: $manifest"
    fi
  }

  # Extract fields from workflow
  local depth app_zone_access gates verification
  depth=$(echo "$workflow" | jq -r '.depth // "full"')
  app_zone_access=$(echo "$workflow" | jq -r '.app_zone_access // false')
  gates=$(echo "$workflow" | jq -c '.gates // {}')
  verification=$(echo "$workflow" | jq -c '.verification // {"method": "test"}')

  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Write state file
  mkdir -p "$(dirname "$STATE_FILE")"
  jq -cn \
    --arg construct "$construct" \
    --arg slug "$slug" \
    --arg manifest_path "$manifest" \
    --arg activated_at "$timestamp" \
    --arg depth "$depth" \
    --argjson app_zone_access "$app_zone_access" \
    --argjson gates "$gates" \
    --argjson verification "$verification" \
    '{
      construct: $construct,
      slug: $slug,
      manifest_path: $manifest_path,
      activated_at: $activated_at,
      depth: $depth,
      app_zone_access: $app_zone_access,
      gates: $gates,
      verification: $verification
    }' > "$STATE_FILE"

  # Compute which constraints would yield
  local yielded_constraints="[]"
  local prd_gate sdd_gate sprint_gate review_gate audit_gate
  prd_gate=$(echo "$gates" | jq -r '.prd // "full"')
  sdd_gate=$(echo "$gates" | jq -r '.sdd // "full"')
  sprint_gate=$(echo "$gates" | jq -r '.sprint // "full"')
  review_gate=$(echo "$gates" | jq -r '.review // "textual"')
  audit_gate=$(echo "$gates" | jq -r '.audit // "full"')

  # C-PROC-001/003 yield when construct has implement: required (always true if validation passed)
  yielded_constraints=$(echo "$yielded_constraints" | jq '. + ["C-PROC-001", "C-PROC-003"]')

  # C-PROC-004 yields when review or audit is skip
  if [[ "$review_gate" == "skip" || "$audit_gate" == "skip" ]]; then
    yielded_constraints=$(echo "$yielded_constraints" | jq '. + ["C-PROC-004"]')
  fi

  # C-PROC-008 yields when sprint is skip
  if [[ "$sprint_gate" == "skip" ]]; then
    yielded_constraints=$(echo "$yielded_constraints" | jq '. + ["C-PROC-008"]')
  fi

  # Log lifecycle event
  log_audit "$(jq -cn \
    --arg ts "$timestamp" \
    --arg construct "$slug" \
    --arg depth "$depth" \
    --argjson gates "$gates" \
    --argjson yielded "$yielded_constraints" \
    '{
      timestamp: $ts,
      event: "construct.workflow.started",
      construct: $construct,
      depth: $depth,
      gates: $gates,
      constraints_yielded: $yielded
    }')"

  echo "Construct workflow activated: $construct ($slug)"
  echo "Depth: $depth | Gates: $(echo "$gates" | jq -c '.')"
}

cmd_deactivate() {
  local complete_sprint=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --complete) complete_sprint="$2"; shift 2 ;;
      *)          die "Unknown option: $1" ;;
    esac
  done

  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local outcome="success"
  local duration_seconds=0

  # Read current state for logging
  if [[ -f "$STATE_FILE" ]]; then
    local slug activated_at
    slug=$(jq -r '.slug' "$STATE_FILE")
    activated_at=$(jq -r '.activated_at' "$STATE_FILE")

    # Calculate duration
    local start_epoch end_epoch
    start_epoch=$(date -d "$activated_at" +%s 2>/dev/null || echo 0)
    end_epoch=$(date +%s)
    if [[ "$start_epoch" -gt 0 ]]; then
      duration_seconds=$((end_epoch - start_epoch))
    fi

    # Log lifecycle event
    log_audit "$(jq -cn \
      --arg ts "$timestamp" \
      --arg construct "$slug" \
      --arg outcome "$outcome" \
      --argjson duration "$duration_seconds" \
      '{
        timestamp: $ts,
        event: "construct.workflow.completed",
        construct: $construct,
        outcome: $outcome,
        duration_seconds: $duration
      }')"

    # Remove state file
    rm -f "$STATE_FILE"
    echo "Construct workflow deactivated: $slug"
  else
    echo "No active construct workflow to deactivate."
  fi

  # Create COMPLETED marker if requested
  if [[ -n "$complete_sprint" ]]; then
    local completed_dir="${REPO_ROOT}/grimoires/loa/a2a/${complete_sprint}"
    mkdir -p "$completed_dir"
    echo "COMPLETED at $timestamp by construct workflow" > "${completed_dir}/COMPLETED"
    echo "Created COMPLETED marker for $complete_sprint"
  fi

  return 0
}

cmd_check() {
  if [[ -f "$STATE_FILE" ]]; then
    # Staleness check: ignore if >24h old
    local activated_at
    activated_at=$(jq -r '.activated_at' "$STATE_FILE" 2>/dev/null || echo "")
    if [[ -n "$activated_at" ]]; then
      local start_epoch now_epoch age_hours
      start_epoch=$(date -d "$activated_at" +%s 2>/dev/null || echo 0)
      now_epoch=$(date +%s)
      if [[ "$start_epoch" -gt 0 ]]; then
        age_hours=$(( (now_epoch - start_epoch) / 3600 ))
        if [[ "$age_hours" -ge 24 ]]; then
          echo "STALE: construct-workflow.json is ${age_hours}h old (>24h), treating as inactive" >&2
          exit 1
        fi
      fi
    fi

    cat "$STATE_FILE"
    exit 0
  else
    exit 1
  fi
}

cmd_gate() {
  local gate="${1:-}"
  [[ -z "$gate" ]] && die "Usage: $0 gate <gate_name>"

  if [[ ! -f "$STATE_FILE" ]]; then
    exit 1
  fi

  # Staleness check
  local activated_at
  activated_at=$(jq -r '.activated_at' "$STATE_FILE" 2>/dev/null || echo "")
  if [[ -n "$activated_at" ]]; then
    local start_epoch now_epoch age_hours
    start_epoch=$(date -d "$activated_at" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    if [[ "$start_epoch" -gt 0 ]]; then
      age_hours=$(( (now_epoch - start_epoch) / 3600 ))
      if [[ "$age_hours" -ge 24 ]]; then
        exit 1
      fi
    fi
  fi

  local value
  value=$(jq -r --arg g "$gate" '.gates[$g] // empty' "$STATE_FILE")
  if [[ -z "$value" ]]; then
    die "Gate '$gate' not found in active construct workflow"
  fi
  echo "$value"
}

# ── Main ───────────────────────────────────────────────

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    activate)   cmd_activate "$@" ;;
    deactivate) cmd_deactivate "$@" ;;
    check)      cmd_check ;;
    gate)       cmd_gate "$@" ;;
    *)          echo "Usage: $0 {activate|deactivate|check|gate} [args...]" >&2; exit 2 ;;
  esac
}

main "$@"
